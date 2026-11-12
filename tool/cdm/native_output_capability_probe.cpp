// Read-only Windows output capability diagnostic. Does not configure protection,
// load a CDM, request a license, or report guessed status to a CDM.
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <d3d9.h>
#include <opmapi.h>
#include <wincrypt.h>
#include <cstdio>
#include <vector>

namespace {
void InspectCertificate(const BYTE* data, ULONG size) {
  CRYPT_DATA_BLOB blob{size, const_cast<BYTE*>(data)};
  HCERTSTORE store = nullptr;
  HCRYPTMSG message = nullptr;
  DWORD content = 0;
  const void* context = nullptr;
  const bool parsed = CryptQueryObject(CERT_QUERY_OBJECT_BLOB, &blob,
      CERT_QUERY_CONTENT_FLAG_CERT | CERT_QUERY_CONTENT_FLAG_PKCS7_SIGNED |
          CERT_QUERY_CONTENT_FLAG_PKCS7_UNSIGNED,
      CERT_QUERY_FORMAT_FLAG_BINARY, 0, nullptr, &content, nullptr,
      &store, &message, &context) != FALSE;
  printf("opm_certificate_parsed=%u content_type=%lu win32=%lu\n",
         parsed ? 1u : 0u, content, parsed ? 0 : GetLastError());
  if (parsed && store) {
    unsigned certificates = 0;
    PCCERT_CONTEXT certificate = nullptr;
    while ((certificate = CertEnumCertificatesInStore(store, certificate))) {
      ++certificates;
      CERT_CHAIN_PARA parameters{};
      parameters.cbSize = sizeof(parameters);
      PCCERT_CHAIN_CONTEXT chain = nullptr;
      // No certificate downloads or changes to the machine trust store.
      const bool built = CertGetCertificateChain(nullptr, certificate, nullptr,
          store, &parameters, CERT_CHAIN_CACHE_ONLY_URL_RETRIEVAL |
              CERT_CHAIN_DISABLE_AUTH_ROOT_AUTO_UPDATE, nullptr, &chain) != FALSE;
      printf("opm_certificate_index=%u chain_built=%u", certificates - 1,
             built ? 1u : 0u);
      if (built && chain) {
        CERT_CHAIN_POLICY_PARA policy_parameters{};
        policy_parameters.cbSize = sizeof(policy_parameters);
        CERT_CHAIN_POLICY_STATUS policy_status{};
        policy_status.cbSize = sizeof(policy_status);
        const bool checked = CertVerifyCertificateChainPolicy(
            CERT_CHAIN_POLICY_MICROSOFT_ROOT, chain, &policy_parameters,
            &policy_status) != FALSE;
        printf(" chain_errors=0x%08lX microsoft_root_checked=%u "
               "policy_error=0x%08lX", chain->TrustStatus.dwErrorStatus,
               checked ? 1u : 0u, policy_status.dwError);
        CertFreeCertificateChain(chain);
      }
      printf("\n");
    }
    printf("opm_certificate_count=%u\n", certificates);
  }
  if (context && content == CERT_QUERY_CONTENT_CERT)
    CertFreeCertificateContext(static_cast<PCCERT_CONTEXT>(context));
  if (message) CryptMsgClose(message);
  if (store) CertCloseStore(store, 0);
}

struct MonitorSummary {
  unsigned monitors = 0;
  unsigned opm_outputs = 0;
  unsigned initialized_outputs = 0;
};

BOOL CALLBACK InspectMonitor(HMONITOR monitor, HDC, LPRECT, LPARAM opaque) {
  auto& summary = *reinterpret_cast<MonitorSummary*>(opaque);
  const auto index = summary.monitors++;
  ULONG count = 0;
  IOPMVideoOutput** outputs = nullptr;
  const auto result = OPMGetVideoOutputsFromHMONITOR(
      monitor, OPM_VOS_OPM_SEMANTICS, &count, &outputs);
  printf("monitor=%u opm_enumeration_hresult=0x%08lX outputs=%lu\n",
         index, static_cast<unsigned long>(result), count);
  if (SUCCEEDED(result) && outputs) {
    summary.opm_outputs += count;
    for (ULONG i = 0; i < count; ++i) {
      if (!outputs[i]) continue;
      OPM_RANDOM_NUMBER random{};
      BYTE* certificate = nullptr;
      ULONG certificate_size = 0;
      const auto initialization = outputs[i]->StartInitialization(
          &random, &certificate, &certificate_size);
      printf("monitor=%u output=%lu opm_initialization_hresult=0x%08lX "
             "certificate_present=%u\n", index, i,
             static_cast<unsigned long>(initialization),
             certificate && certificate_size ? 1u : 0u);
      if (SUCCEEDED(initialization)) ++summary.initialized_outputs;
      if (SUCCEEDED(initialization) && certificate && certificate_size)
        InspectCertificate(certificate, certificate_size);
      // Do not persist driver certificates or handshake material.
      if (certificate) {
        SecureZeroMemory(certificate, certificate_size);
        CoTaskMemFree(certificate);
      }
      SecureZeroMemory(&random, sizeof(random));
      outputs[i]->Release();
    }
  }
  if (outputs) CoTaskMemFree(outputs);
  return TRUE;
}

const char* LinkType(DISPLAYCONFIG_VIDEO_OUTPUT_TECHNOLOGY technology) {
  switch (technology) {
    case DISPLAYCONFIG_OUTPUT_TECHNOLOGY_INTERNAL:
    case DISPLAYCONFIG_OUTPUT_TECHNOLOGY_DISPLAYPORT_EMBEDDED:
    case DISPLAYCONFIG_OUTPUT_TECHNOLOGY_UDI_EMBEDDED: return "internal";
    case DISPLAYCONFIG_OUTPUT_TECHNOLOGY_HD15: return "vga";
    case DISPLAYCONFIG_OUTPUT_TECHNOLOGY_DVI: return "dvi";
    case DISPLAYCONFIG_OUTPUT_TECHNOLOGY_HDMI: return "hdmi";
    case DISPLAYCONFIG_OUTPUT_TECHNOLOGY_DISPLAYPORT_EXTERNAL: return "displayport";
    case DISPLAYCONFIG_OUTPUT_TECHNOLOGY_MIRACAST: return "wireless";
    case DISPLAYCONFIG_OUTPUT_TECHNOLOGY_INDIRECT_WIRED: return "indirect_wired";
    default: return "unknown";
  }
}
}  // namespace

int main() {
  const auto com = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  printf("com_hresult=0x%08lX remote_session=%u\n",
         static_cast<unsigned long>(com),
         GetSystemMetrics(SM_REMOTESESSION) ? 1u : 0u);
  if (FAILED(com)) return 1;
  LONG topology = ERROR_INSUFFICIENT_BUFFER;
  for (unsigned attempt = 0; attempt < 3 &&
       topology == ERROR_INSUFFICIENT_BUFFER; ++attempt) {
    UINT32 path_count = 0, mode_count = 0;
    topology = GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS,
                                           &path_count, &mode_count);
    if (topology != ERROR_SUCCESS) break;
    std::vector<DISPLAYCONFIG_PATH_INFO> paths(path_count);
    std::vector<DISPLAYCONFIG_MODE_INFO> modes(mode_count);
    topology = QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, &path_count,
        paths.data(), &mode_count, modes.data(), nullptr);
    if (topology == ERROR_SUCCESS) {
      printf("active_display_paths=%u\n", path_count);
      for (UINT32 i = 0; i < path_count; ++i) {
        printf("display_path=%u link=%s\n", i,
               LinkType(paths[i].targetInfo.outputTechnology));
      }
    }
  }
  printf("display_topology_win32=%ld\n", topology);
  MonitorSummary summary;
  const auto enumerated = EnumDisplayMonitors(nullptr, nullptr, InspectMonitor,
                                               reinterpret_cast<LPARAM>(&summary));
  printf("monitor_enumeration_ok=%u monitors=%u opm_outputs=%u "
         "opm_initializations=%u\n", enumerated ? 1u : 0u, summary.monitors,
         summary.opm_outputs, summary.initialized_outputs);
  // An OPM object or driver certificate does not prove HDCP status. A complete
  // authenticated OPM handshake and status query would still be required.
  printf("hdcp_status=not_queried license_requests_sent=0\n");
  CoUninitialize();
  return topology == ERROR_SUCCESS && enumerated ? 0 : 2;
}
