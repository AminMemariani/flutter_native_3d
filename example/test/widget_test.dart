import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_native_3d_example/main.dart';

void main() {
  testWidgets('app launches without error', (tester) async {
    await tester.pumpWidget(const Native3DShowcase());
    // The 3D viewer requires a real platform view, so we just verify
    // the widget tree builds without throwing.
    expect(find.text('Damaged Helmet'), findsOneWidget);
  });
}
