import 'dart:io';

void appLog(String msg) {
  try {
    final f = File('C:\\tmp\\app_debug.log');
    f.writeAsStringSync(
      '${DateTime.now().toIso8601String()} $msg\n',
      mode: FileMode.append,
      flush: true,
    );
  } catch (_) {}
}
