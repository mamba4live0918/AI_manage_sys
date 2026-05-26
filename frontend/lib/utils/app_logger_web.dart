import 'package:flutter/foundation.dart';

void logImpl(String msg) {
  debugPrint('[${DateTime.now().toIso8601String()}] $msg');
}
