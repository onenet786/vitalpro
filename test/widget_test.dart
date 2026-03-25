import 'package:flutter_test/flutter_test.dart';

import 'package:vitalpro/main.dart';

void main() {
  testWidgets('launch gate renders security prompt', (tester) async {
    await tester.pumpWidget(const VitalProApp());

    expect(find.text('Launch Security'), findsOneWidget);
    expect(find.text('Unlock'), findsOneWidget);
  });
}
