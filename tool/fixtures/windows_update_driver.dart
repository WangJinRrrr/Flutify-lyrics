import 'dart:convert';
import 'dart:io';

import '../../lib/services/updates/windows_update_runner.dart';

Future<void> main(List<String> args) async {
  final plan = File(args[1]);
  final data = jsonDecode(await plan.readAsString()) as Map<String, dynamic>;
  data['processId'] = pid;
  await plan.writeAsString(jsonEncode(data));
  await launchWindowsUpdateHelper(script: File(args[0]), plan: plan);
  stdout.writeln('ready');
  // Keep the simulated app alive until the test permits normal shutdown.
  await stdin.first;
}
