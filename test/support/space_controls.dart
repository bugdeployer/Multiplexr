import 'package:flutter_test/flutter_test.dart';

/// Open the disclosure before exercising the existing browse/filter workflows.
Future<void> openSpaceControls(WidgetTester tester) async {
  final toggle = find.textContaining(RegExp(r'^(Overview|Browse) & filters$'));
  if (toggle.evaluate().isEmpty) return;
  await tester.ensureVisible(toggle.first);
  await tester.tap(toggle.first);
  await tester.pumpAndSettle();
}
