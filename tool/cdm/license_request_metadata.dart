// Read-only, bounded inspection for the opt-in CDM comparison. Never returns
// payload bytes, identifiers, nonces, signatures, keys, or server text.
// Field numbers follow Widevine's published license_protocol.proto schema.
import 'dart:typed_data';

Map<String, Object?> licenseRequestMetadata(
  Uint8List bytes, {
  required Uint8List pssh,
  required Uint8List certificate,
  DateTime? now,
}) {
  try {
    final envelope = _Message(bytes);
    final result = <String, Object?>{
      'bytes': bytes.length,
      'message': _enum(envelope.number(1), {
        1: 'license_request',
        5: 'certificate',
      }),
      'signature_bytes': envelope.bytes(3)?.length ?? 0,
      'session_key_bytes': envelope.bytes(4)?.length ?? 0,
      'remote_attestation_present': envelope.bytes(5) != null,
      'oemcrypto_core_present': envelope.bytes(9) != null,
    };
    if (envelope.number(1) != 1) return result;
    final request = _Message(envelope.requiredBytes(2));
    final time = request.number(4);
    final seconds = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
    result.addAll({
      'request': _enum(request.number(3), {
        1: 'new',
        2: 'renewal',
        3: 'release',
      }),
      'protocol': _enum(request.number(6) ?? 20, {
        20: '2.0',
        21: '2.1',
        22: '2.2',
      }),
      'time_within_5m': time == null ? null : (seconds - time).abs() <= 300,
      'nonce_present': request.number(7) != null || request.bytes(5) != null,
      'plaintext_client_id': request.bytes(1) != null,
      'encrypted_client_id': request.bytes(8) != null,
    });
    final content = _Message(request.requiredBytes(2));
    if (content.bytes(1) case final data?) {
      final widevine = _Message(data);
      final payloads = widevine.repeatedBytes(1);
      result.addAll({
        'content': 'widevine_pssh',
        'pssh_count': payloads.length,
        'pssh_matches_input':
            payloads.length == 1 && _equal(payloads.single, _psshPayload(pssh)),
        'license_type': _licenseType(widevine.number(2)),
        'request_id_bytes': widevine.bytes(3)?.length ?? 0,
      });
    } else if (content.bytes(4) case final data?) {
      final init = _Message(data);
      result.addAll({
        'content': 'init_data',
        'pssh_matches_input': _equal(init.bytes(2), pssh),
        'license_type': _licenseType(init.number(3)),
        'request_id_bytes': init.bytes(4)?.length ?? 0,
      });
    } else {
      result['content'] = content.bytes(3) != null
          ? 'existing_license'
          : 'other';
    }
    if (request.bytes(8) case final data?) {
      final encrypted = _Message(data);
      result.addAll({
        'client_ciphertext_bytes': encrypted.bytes(3)?.length ?? 0,
        'client_iv_bytes': encrypted.bytes(4)?.length ?? 0,
        'privacy_key_bytes': encrypted.bytes(5)?.length ?? 0,
        // VMP is inside the encrypted identification: it cannot be inspected.
        'vmp': 'encrypted_unobservable',
      });
      try {
        final signed = _Message(certificate);
        Uint8List certBytes;
        try {
          certBytes = signed.requiredBytes(1);
        } on FormatException {
          if (signed.number(1) != 5) rethrow;
          certBytes = _Message(signed.requiredBytes(2)).requiredBytes(1);
        }
        final cert = _Message(certBytes);
        result['certificate_provider_matches'] = _equal(
          encrypted.bytes(1),
          cert.bytes(7),
        );
        result['certificate_serial_matches'] = _equal(
          encrypted.bytes(2),
          cert.bytes(2),
        );
      } on FormatException {
        result['certificate_comparison'] = 'unavailable';
      }
    } else if (request.bytes(1) case final data?) {
      final client = _Message(data);
      final vmp = client.bytes(7);
      result['vmp'] = vmp == null || vmp.isEmpty ? 'absent' : 'present';
      if (vmp != null && vmp.isNotEmpty) {
        result['vmp_file_count'] = _Message(vmp).repeatedBytes(2).length;
      }
    }
    return result;
  } on FormatException {
    return {'bytes': bytes.length, 'inspection': 'malformed_or_unsupported'};
  }
}

String _enum(int? value, Map<int, String> values) =>
    value == null ? 'absent' : values[value] ?? 'unknown';

String _licenseType(int? value) =>
    _enum(value, {1: 'streaming', 2: 'offline', 3: 'automatic'});

bool _equal(Uint8List? a, Uint8List? b) {
  if (a == null || b == null || a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

Uint8List _psshPayload(Uint8List box) {
  if (box.length < 32) throw const FormatException();
  final data = ByteData.sublistView(box);
  if (data.getUint32(0) != box.length ||
      data.getUint32(4) != 0x70737368 ||
      box[8] > 1) {
    throw const FormatException();
  }
  var offset = 28;
  if (box[8] == 1) offset += 4 + data.getUint32(28) * 16;
  if (offset + 4 > box.length ||
      data.getUint32(offset) != box.length - offset - 4) {
    throw const FormatException();
  }
  return Uint8List.sublistView(box, offset + 4);
}

class _Message {
  _Message(Uint8List input) {
    if (input.length > 1024 * 1024) throw const FormatException();
    var offset = 0;
    int varint() {
      var value = 0;
      for (var i = 0; i < 10; i++) {
        if (offset >= input.length) throw const FormatException();
        final byte = input[offset++];
        if (i == 9 && byte > 1) throw const FormatException();
        value |= (byte & 0x7f) << (i * 7);
        if (byte < 128) return value;
      }
      throw const FormatException();
    }

    var count = 0;
    while (offset < input.length) {
      if (++count > 2048) throw const FormatException();
      final tag = varint();
      final field = tag >> 3;
      if (field <= 0 || field > 0x1fffffff) throw const FormatException();
      final wire = tag & 7;
      if (wire == 0) {
        (_fields[field] ??= []).add((wire, varint()));
        continue;
      }
      final length = switch (wire) {
        1 => 8,
        2 => varint(),
        5 => 4,
        _ => throw const FormatException(),
      };
      if (length < 0 || length > input.length - offset) {
        throw const FormatException();
      }
      (_fields[field] ??= []).add((
        wire,
        Uint8List.sublistView(input, offset, offset + length),
      ));
      offset += length;
    }
  }

  final _fields = <int, List<(int, Object)>>{};

  Object? _single(int field, int wire) {
    final entries = _fields[field];
    if (entries == null) return null;
    if (entries.length != 1 || entries.single.$1 != wire) {
      throw const FormatException();
    }
    return entries.single.$2;
  }

  int? number(int field) => _single(field, 0) as int?;
  Uint8List? bytes(int field) => _single(field, 2) as Uint8List?;
  Uint8List requiredBytes(int field) =>
      bytes(field) ?? (throw const FormatException());
  List<Uint8List> repeatedBytes(int field) => [
    for (final entry in _fields[field] ?? <(int, Object)>[])
      if (entry.$1 == 2)
        entry.$2 as Uint8List
      else
        throw const FormatException(),
  ];
}
