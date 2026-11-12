// 扫描 Spotify 进程内存：找 OggS/SpAC 明文音频区 + playplay 响应字节（R1）邻域。
// 用法: memscan.exe <pid> <r1_hex> [dump_dir]
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

static void* memmem(const void* h, size_t hl, const void* n, size_t nl) {
    if (nl == 0 || hl < nl) return nullptr;
    for (size_t i = 0; i + nl <= hl; i++)
        if (memcmp((const uint8_t*)h + i, n, nl) == 0) return (void*)((const uint8_t*)h + i);
    return nullptr;
}

static std::vector<uint8_t> hex2bin(const char* s) {
    std::vector<uint8_t> out;
    for (size_t i = 0; s[i] && s[i + 1]; i += 2) {
        unsigned v = 0;
        sscanf(s + i, "%2x", &v);
        out.push_back((uint8_t)v);
    }
    return out;
}

int wmain(int argc, wchar_t** argv) {
    if (argc < 3) { printf("usage: memscan <pid> <r1_hex> [dumpdir]\n"); return 1; }
    DWORD pid = _wtoi(argv[1]);
    char hexr1[256] = {0};
    WideCharToMultiByte(CP_ACP, 0, argv[2], -1, hexr1, sizeof(hexr1), NULL, NULL);
    std::string dumpdir = "D:\\tmp\\memdump";
    std::vector<uint8_t> r1 = hex2bin(hexr1);

    HANDLE h = OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, FALSE, pid);
    if (!h) { printf("OpenProcess failed %lu\n", GetLastError()); return 2; }
    CreateDirectoryA(dumpdir.c_str(), NULL);

    // 额外搜索：密文前缀（下载缓冲）与 R1
    std::vector<std::pair<std::string, std::vector<uint8_t>>> pats;
    pats.push_back({"ciph574", hex2bin("c94c585c3551206cda9ec22950050846")});
    pats.push_back({"ciph5353", hex2bin("45833ef41fcd99782a32a28c29cc2b0d")});
    if (!r1.empty()) pats.push_back({"R1", r1});

    MEMORY_BASIC_INFORMATION mbi;
    uint8_t* p = nullptr;
    int nregions = 0, hits = 0;
    std::vector<uint8_t> buf;
    while (VirtualQueryEx(h, p, &mbi, sizeof(mbi)) == sizeof(mbi)) {
        if (mbi.State == MEM_COMMIT && (mbi.Protect & (PAGE_READWRITE | PAGE_READONLY | PAGE_EXECUTE_READ | PAGE_EXECUTE_READWRITE | PAGE_WRITECOPY | PAGE_EXECUTE_WRITECOPY)) && !(mbi.Protect & PAGE_GUARD)) {
            size_t size = mbi.RegionSize;
            if (size > 0 && size < (size_t)512 * 1024 * 1024) {
                buf.resize(size);
                SIZE_T got = 0;
                if (ReadProcessMemory(h, mbi.BaseAddress, buf.data(), size, &got) && got > 0) {
                    nregions++;
                    // 1) OggS / SpAC 大区域
                    size_t i = 0;
                    while (i + 4 < got) {
                        uint8_t* found = (uint8_t*)memmem(buf.data() + i, got - i, "OggS", 4);
                        if (!found) { 
                            found = (uint8_t*)memmem(buf.data() + i, got - i, "SpAC", 4);
                            if (!found) break;
                        }
                        size_t off = found - buf.data();
                        // 估算后续长度：找下一个非 OggS 连续大块（粗略：统计 OggS 出现次数）
                        size_t cnt = 0;
                        for (size_t j = off; j + 4 < got; j++) {
                            uint8_t* f2 = (uint8_t*)memmem(buf.data() + j, got - j, "OggS", 4);
                            if (!f2) break;
                            cnt++; j = f2 - buf.data();
                        }
                        printf("[mem] %s @region=%p off=0x%zx  后续OggS计数=%zu\n",
                               found[0] == 'O' ? "OggS" : "SpAC", mbi.BaseAddress, off, cnt);
                        char name[256];
                        sprintf(name, "%s\\region_%p_%zx.bin", dumpdir.c_str(), mbi.BaseAddress, off);
                        FILE* f = fopen(name, "wb");
                        if (f) { fwrite(buf.data() + off, 1, got - off, f); fclose(f); printf("    dumped -> %s (%zu bytes)\n", name, got - off); }
                        hits++;
                        i = off + 4;
                        if (hits > 40) break;
                    }
                    // 2) R1 邻域：打印前后 + 落盘前后各2KB供离线分析
                    if (!r1.empty()) {
                        i = 0;
                        int ndump = 0;
                        while (i + r1.size() < got) {
                            uint8_t* f3 = (uint8_t*)memmem(buf.data() + i, got - i, r1.data(), r1.size());
                            if (!f3) break;
                            size_t off = f3 - buf.data();
                            printf("[R1] @%p off=0x%zx  前32B:", mbi.BaseAddress, off);
                            for (size_t k = 0; k < 32 && off >= 32; k++) printf(" %02x", buf[off - 32 + k]);
                            printf("\n     R1本身+后64B:");
                            for (size_t k = 0; k < r1.size() + 64 && off + k < got; k++) printf(" %02x", buf[off + k]);
                            printf("\n");
                            size_t lo = off > 2048 ? off - 2048 : 0;
                            size_t hi = off + r1.size() + 2048 < got ? off + r1.size() + 2048 : got;
                            char name[256];
                            sprintf(name, "%s\\keyctx_%p_%zx.bin", dumpdir.c_str(), mbi.BaseAddress, off);
                            FILE* f = fopen(name, "wb");
                            if (f && ndump < 12) { fwrite(buf.data() + lo, 1, hi - lo, f); fclose(f); printf("    keyctx -> %s (%zu bytes)\n", name, hi - lo); ndump++; }
                            i = off + r1.size();
                        }
                    }
                    // 3) 自定义模式：密文前缀 / R1
                    for (auto& pp : pats) {
                        const std::string& pname = pp.first;
                        const std::vector<uint8_t>& pat = pp.second;
                        size_t j = 0;
                        while (j + pat.size() < got) {
                            uint8_t* f4 = (uint8_t*)memmem(buf.data() + j, got - j, pat.data(), pat.size());
                            if (!f4) break;
                            size_t off2 = f4 - buf.data();
                            printf("[%s] @%p off=0x%zx  前16B:", pname.c_str(), mbi.BaseAddress, off2);
                            for (size_t k = 0; k < 16 && off2 >= 16; k++) printf(" %02x", buf[off2 - 16 + k]);
                            printf("  后32B:");
                            for (size_t k = 0; k < 32 && off2 + k < got; k++) printf(" %02x", buf[off2 + k]);
                            printf("\n");
                            j = off2 + pat.size();
                        }
                    }
                }
            }
        }
        p += mbi.RegionSize;
        if (hits > 40) break;
    }
    printf("regions read: %d  hits: %d\n", nregions, hits);
    CloseHandle(h);
    return 0;
}
