import 'dart:io';

/// Launch independently through Windows PowerShell, without DETACHED_PROCESS.
/// Returns only after the helper is ready and this operation is committed.
Future<void> launchWindowsUpdateHelper({
  required File script,
  required File plan,
}) async {
  final powershell =
      '${Platform.environment['SystemRoot'] ?? r'C:\Windows'}'
      r'\System32\WindowsPowerShell\v1.0\powershell.exe';
  final operation = plan.absolute.parent;
  File marker(String name) => File.fromUri(operation.uri.resolve(name));
  final args = [
    '-NoProfile',
    '-NonInteractive',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    script.absolute.path,
    '-PlanPath',
    plan.absolute.path,
  ];
  try {
    final prepared = await Process.run(powershell, [...args, '-PrepareOnly']);
    if (prepared.exitCode != 0) {
      throw StateError('Unable to prepare update: ${prepared.stderr}');
    }
    // Windows PowerShell 5.1 silently exits with Dart's DETACHED_PROCESS flag.
    // A short-lived launcher uses Start-Process -WindowStyle Hidden so the
    // helper survives app shutdown without inheriting Dart's pipes.
    final launched = await Process.run(powershell, [...args, '-LaunchHelper']);
    if (launched.exitCode != 0) {
      throw StateError('Unable to launch update helper: ${launched.stderr}');
    }
    for (var i = 0; i < 100; i++) {
      if (await marker('error.txt').exists()) break;
      if (await marker('waiting').exists()) {
        await marker('commit').writeAsString('commit', flush: true);
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw StateError('Timed out waiting for update helper');
  } catch (error) {
    // A slow helper must not apply an abandoned operation on a later app exit.
    await marker('cancelled').writeAsString('cancelled', flush: true);
    final failure = marker('error.txt');
    final host = marker('host.txt');
    final details = await failure.exists()
        ? (await failure.readAsString()).trim()
        : error.toString();
    final version = await host.exists()
        ? (await host.readAsString()).trim()
        : powershell;
    throw StateError('$details ($version; diagnostics: ${operation.path})');
  }
}
