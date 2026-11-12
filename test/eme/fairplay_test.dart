import 'package:flutify_app/services/eme/fairplay.dart';
import 'package:flutify_app/services/eme/license_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('fairplay.dart', () {
    test('端点：license 带 ?assetId=hex，证书走 application-certificate', () {
      expect(
        fairPlayLicenseUri('spclient.wg.spotify.com').toString(),
        'https://spclient.wg.spotify.com/fairplay-license/v1/audio/license?assetId=hex',
      );
      expect(
        fairPlayCertUri('spclient.wg.spotify.com').toString(),
        'https://spclient.wg.spotify.com/fairplay-license/v1/application-certificate',
      );
    });

    test('KEY 行：URI 为 skd:// + file_id（JS 过滤器剥 scheme 后喂 CDM）', () {
      const fid = '3bcdc419c0eba8a063ea516f4f36b18ad5cc6079';
      expect(
        fairPlayKeyLine(fid),
        '#EXT-X-KEY:METHOD=SAMPLE-AES,URI="skd://$fid",'
        'KEYFORMATVERSIONS="1",KEYFORMAT="com.apple.streamingkeydelivery"',
      );
    });

    test('useFairPlay 可被测试覆盖（macOS / iOS 走 FairPlay，其余 Widevine）', () {
      addTearDown(() => debugUseFairPlayOverride = null);
      debugUseFairPlayOverride = true;
      expect(useFairPlay, isTrue);
      final c = WidevineLicenseClient(
        webToken: () async => '',
        clientToken: () async => '',
      );
      expect(c.effectiveDrmSystem, EmeDrmSystem.fairplay);
      debugUseFairPlayOverride = false;
      expect(useFairPlay, isFalse);
      expect(c.effectiveDrmSystem, EmeDrmSystem.widevine);
    });
  });
}
