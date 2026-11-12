import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Dart uses bundled roots on Windows, while WebView2 uses Windows trust.
/// Add system-trusted roots before creating clients; never bypass TLS checks.
class WindowsTrustStore {
  static const channel = MethodChannel('flutify/windows_trust_store');

  static Future<void> initialize() async {
    if (!Platform.isWindows) return;
    await loadInto(SecurityContext.defaultContext);
  }

  @visibleForTesting
  static Future<int> loadInto(SecurityContext context) async {
    var loaded = 0;
    try {
      final certificates = await channel.invokeListMethod<Uint8List>('roots');
      for (final der in certificates ?? <Uint8List>[]) {
        try {
          final pem =
              '-----BEGIN CERTIFICATE-----\n'
              '${base64Encode(der)}\n-----END CERTIFICATE-----\n';
          context.setTrustedCertificatesBytes(utf8.encode(pem));
          loaded++;
        } on TlsException {
          // An unsupported system certificate must not discard the other roots.
          debugPrint('[TLS] Skipped an unsupported Windows root certificate');
        }
      }
      debugPrint('[TLS] Loaded $loaded Windows root certificates');
    } on PlatformException catch (e) {
      debugPrint(
        '[TLS] Windows roots unavailable (${e.code}); using Dart roots',
      );
    } on MissingPluginException {
      debugPrint('[TLS] Windows trust channel unavailable; using Dart roots');
    }
    return loaded;
  }
}
