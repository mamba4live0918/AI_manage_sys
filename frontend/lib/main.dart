import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'utils/app_logger.dart';

void main() {
  appLog('[MAIN] Starting app...');
  WidgetsFlutterBinding.ensureInitialized();
  appLog('[MAIN] Binding initialized, running app...');
  runApp(const ProviderScope(child: AIManageApp()));
  appLog('[MAIN] runApp called');
}
