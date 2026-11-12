import 'dart:typed_data';

/// Shannon 流密码（Spotify Access Point 通道加密）。
///
/// 移植自 despotify / shannon crate (Rust, MIT) / librespot-java 三份实现，
/// 取「按完整字才折入 MAC」的 C/Java 语义（`macfunc` 只在 32 位字凑齐时调用一次）。
/// 该语义与调用分块无关（chunk-invariant）；AP 报文编解码按 librespot `ApCodec`
/// 的调用结构（每包一次 encrypt、decrypt 拆 头/体 两次）组织，两种流传现语义在此
/// 结构下输出一致。
///
/// 协议要点（`docs/connection.md`）：
/// - 发送/接收各自独立的 Shannon 实例与 nonce；
/// - 每包以 4 字节大端 nonce 重新播种（自 0 递增）；
/// - 包格式：cmd(1) + len(2 BE) + payload + mac(4)，mac 由 finish() 产出。
class Shannon {
  static const int _n = 16;
  static const int _fold = 16;
  static const int _initKonst = 0x6996c53a;
  static const int _keyP = 13;

  final List<int> _r = List<int>.filled(_n, 0);
  final List<int> _crc = List<int>.filled(_n, 0);
  List<int> _initR = List<int>.filled(_n, 0);

  int _konst = _initKonst;
  int _sbuf = 0;
  int _mbuf = 0;
  int _nbuf = 0;

  Shannon(Uint8List key) {
    _r[0] = 1;
    _r[1] = 1;
    for (var i = 2; i < _n; i++) {
      _r[i] = (_r[i - 1] + _r[i - 2]) & 0xffffffff;
    }
    _loadKey(key);
    _genkonst();
    _initR = List<int>.from(_r);
  }

  static int _rotl(int w, int x) => ((w << x) | ((w & 0xffffffff) >> (32 - x))) & 0xffffffff;

  static int _sbox1(int w) {
    w = (w ^ (_rotl(w, 5) | _rotl(w, 7))) & 0xffffffff;
    w = (w ^ (_rotl(w, 19) | _rotl(w, 22))) & 0xffffffff;
    return w;
  }

  static int _sbox2(int w) {
    w = (w ^ (_rotl(w, 7) | _rotl(w, 22))) & 0xffffffff;
    w = (w ^ (_rotl(w, 5) | _rotl(w, 19))) & 0xffffffff;
    return w;
  }

  void _genkonst() => _konst = _r[0];

  void _cycle() {
    var t = _sbox1(_r[12] ^ _r[13] ^ _konst) ^ _rotl(_r[0], 1);
    for (var i = 1; i < _n; i++) {
      _r[i - 1] = _r[i];
    }
    _r[_n - 1] = t;
    t = _sbox2(_r[2] ^ _r[15]);
    _r[0] = (_r[0] ^ t) & 0xffffffff;
    _sbuf = (t ^ _r[8] ^ _r[12]) & 0xffffffff;
  }

  void _diffuse() {
    for (var i = 0; i < _fold; i++) {
      _cycle();
    }
  }

  void _loadKey(Uint8List key) {
    for (var off = 0; off < key.length; off += 4) {
      var word = 0;
      final remain = (key.length - off).clamp(0, 4);
      for (var i = 0; i < remain; i++) {
        word |= key[off + i] << (8 * i);
      }
      _r[_keyP] = (_r[_keyP] ^ word) & 0xffffffff;
      _cycle();
    }
    _r[_keyP] = (_r[_keyP] ^ key.length) & 0xffffffff;
    _cycle();
    for (var i = 0; i < _n; i++) {
      _crc[i] = _r[i];
    }
    _diffuse();
    for (var i = 0; i < _n; i++) {
      _r[i] = (_r[i] ^ _crc[i]) & 0xffffffff;
    }
  }

  /// 以 4 字节大端 nonce 重新播种（每包调用一次）。
  void nonceU32(int nonce) {
    for (var i = 0; i < _n; i++) {
      _r[i] = _initR[i];
    }
    _konst = _initKonst;
    _loadKey(Uint8List.fromList([
      (nonce >> 24) & 0xff,
      (nonce >> 16) & 0xff,
      (nonce >> 8) & 0xff,
      nonce & 0xff,
    ]));
    _genkonst();
    _nbuf = 0;
    _mbuf = 0;
  }

  void _crcfunc(int i) {
    final t = (_crc[0] ^ _crc[2] ^ _crc[15] ^ i) & 0xffffffff;
    for (var j = 1; j < _n; j++) {
      _crc[j - 1] = _crc[j];
    }
    _crc[_n - 1] = t;
  }

  /// 同时喂 CRC 与流寄存器（完整字）。
  void _macfunc(int i) {
    _crcfunc(i);
    _r[_keyP] = (_r[_keyP] ^ i) & 0xffffffff;
  }

  /// 加密 + 累积 MAC（明文计入 MAC）。原地修改 [buf]。
  void encrypt(Uint8List buf) {
    _process(buf, encryptWord: true);
  }

  /// 解密 + 累积 MAC（明文计入 MAC）。原地修改 [buf]。
  void decrypt(Uint8List buf) {
    _process(buf, encryptWord: false);
  }

  void _process(Uint8List buf, {required bool encryptWord}) {
    var i = 0;
    final n = buf.length;

    // 1) 上次调用遗留的半个字：补齐后折一次 MAC（LFSR 无需再 cycle）
    if (_nbuf != 0) {
      while (_nbuf > 0) {
        if (i >= n) return; // 还凑不满一个字
        final b = buf[i];
        if (encryptWord) {
          _mbuf = (_mbuf ^ (b << (32 - _nbuf))) & 0xffffffff;
          buf[i] = b ^ ((_sbuf >> (32 - _nbuf)) & 0xff);
        } else {
          buf[i] = b ^ ((_sbuf >> (32 - _nbuf)) & 0xff);
          _mbuf = (_mbuf ^ (buf[i] << (32 - _nbuf))) & 0xffffffff;
        }
        i++;
        _nbuf -= 8;
      }
      _macfunc(_mbuf);
    }

    // 2) 整字
    final wholeEnd = i + ((n - i) & ~0x3);
    while (i < wholeEnd) {
      _cycle();
      var t = buf[i] | (buf[i + 1] << 8) | (buf[i + 2] << 16) | (buf[i + 3] << 24);
      if (encryptWord) {
        _macfunc(t);
        t = (t ^ _sbuf) & 0xffffffff;
      } else {
        t = (t ^ _sbuf) & 0xffffffff;
        _macfunc(t);
      }
      buf[i] = t & 0xff;
      buf[i + 1] = (t >> 8) & 0xff;
      buf[i + 2] = (t >> 16) & 0xff;
      buf[i + 3] = (t >> 24) & 0xff;
      i += 4;
    }

    // 3) 尾部不足一个字：先 cycle，等凑齐再折 MAC
    if (i < n) {
      _cycle();
      _mbuf = 0;
      _nbuf = 32;
      while (i < n) {
        final b = buf[i];
        if (encryptWord) {
          _mbuf = (_mbuf ^ (b << (32 - _nbuf))) & 0xffffffff;
          buf[i] = b ^ ((_sbuf >> (32 - _nbuf)) & 0xff);
        } else {
          buf[i] = b ^ ((_sbuf >> (32 - _nbuf)) & 0xff);
          _mbuf = (_mbuf ^ (buf[i] << (32 - _nbuf))) & 0xffffffff;
        }
        i++;
        _nbuf -= 8;
      }
    }
  }

  /// 结束当前包：产出 [length] 字节 MAC（不足一个字的尾部按加密零字节处理）。
  Uint8List finish(int length) {
    if (_nbuf != 0) {
      _macfunc(_mbuf);
    }
    _cycle();
    _r[_keyP] = (_r[_keyP] ^ _initKonst ^ ((_nbuf) << 3)) & 0xffffffff;
    _nbuf = 0;
    for (var i = 0; i < _n; i++) {
      _r[i] = (_r[i] ^ _crc[i]) & 0xffffffff;
    }
    _diffuse();

    final out = Uint8List(length);
    var produced = 0;
    while (produced < length) {
      _cycle();
      for (var b = 0; b < 4 && produced < length; b++) {
        out[produced++] = (_sbuf >> (8 * b)) & 0xff;
      }
    }
    return out;
  }
}
