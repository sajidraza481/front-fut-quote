import 'package:flutter_test/flutter_test.dart';
import 'package:frontfut/app/app.dart';
import 'package:frontfut/core/env.dart';

void main() {
  testWidgets('app shell renders', (tester) async {
    await tester.pumpWidget(const FrontfutApp(flavor: Flavor.dev));
    expect(find.text('Frontfut'), findsOneWidget);
  });
}
