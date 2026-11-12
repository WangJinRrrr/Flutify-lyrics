# Flutify Windows libmpv packaging

This is the MIT-licensed native registration shim from `media_kit_libs_windows_audio` 1.0.9.
The local CMake patch adds ARM64, rejects unknown targets, verifies SHA-256 hashes,
and extracts the matching libmpv at configure time. No Dart playback API is changed.

- x64: upstream audio build, 2023-09-24 / `652a1dd`.
- ARM64: media-kit LGPL libmpv build, 2024-10-21 / `0f78584`.
  The upstream audio package has no ARM64 binary; this libmpv includes video support
  but Flutify uses only its audio API. No ANGLE binaries are bundled.

Sources and binary licensing: [THIRD_PARTY_NOTICES.md](../../THIRD_PARTY_NOTICES.md).
CI checks every packaged EXE/DLL machine type before uploading an archive.
