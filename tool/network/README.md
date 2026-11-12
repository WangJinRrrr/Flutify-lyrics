# Local TLS comparison

`tls_client_hello.py` compares fresh ClientHello messages from Dart, Node and a
separate Chrome/Chromium process against a loopback-only listener. It requires
Python 3.9+, Dart, Node and Chrome; `--dart`, `--node` and `--chrome` accept explicit
executable paths if they are not discoverable. Example from the app directory:

```powershell
python tool/network/tls_client_hello.py --dart D:/flutter-sdk/3.44.0/flutter/bin/cache/dart-sdk/bin/dart.exe
```

Results and small generated clients go to ignored `tool/probe_out/tls/` by
default (`--out` overrides this). Chrome uses a new temporary profile, resolves
only `tls-probe.invalid` to loopback, and is stopped after the capture. The tool
does not read an existing browser profile or account data. No application HTTP
request is sent; the listener closes after receiving ClientHello. Production
certificate validation settings are unchanged.

The JSON omits random bytes, session IDs and GREASE values. Compare cipher suite
order, supported groups, signature algorithms, supported versions and ALPN.
Chrome may permute extension order between connections. One successful capture
is **not** proof of matching HTTP/2 settings, session resumption, the deployed
proxy server, or Spotify's desktop client.

Node reproduces the current gateway's TLS options (`rejectUnauthorized: true`,
`minVersion: TLSv1.2`); it is not a capture through the deployed gateway. Dart
exercises `SecureSocket`, not an HTTP request through the full routing layer.
Neither profile is changed by this tool. A future transport replacement needs
fresh captures plus tests of certificate rejection, authenticated CONNECT,
redirect credential isolation, WebSockets, streaming cancellation and gateway
upstream behavior before it can replace the application's existing client.
