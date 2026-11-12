import 'dart:typed_data';

import '../auth/client_profile.dart';
import '../auth/proto_codec.dart';

/// 编码 AP 加密通道内的登录包；不添加应用专用标识。
Uint8List encodeApLoginRequest({
  String? username,
  required int authType,
  required Uint8List authData,
  String? deviceId,
  SpotifyClientProfile profile = SpotifyClientProfile.desktop,
}) {
  final credentials = ProtoWriter()
    ..string(10, username ?? '')
    ..varintAlways(20, authType)
    ..bytes(30, authData);
  return (ProtoWriter()
        ..message(10, credentials)
        ..message(50, profile.apSystemInfo(deviceId))
        ..string(70, profile.clientVersion))
      .toBytes();
}
