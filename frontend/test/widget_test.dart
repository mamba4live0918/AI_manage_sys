import 'package:flutter_test/flutter_test.dart';
import 'package:ai_manage_sys/app.dart';

void main() {
  testWidgets('App renders', (WidgetTester tester) async {
    await tester.pumpWidget(const AIManageApp());
    await tester.pump();
  });
}
