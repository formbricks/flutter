import 'package:flutter_test/flutter_test.dart';
import 'package:formbricks_playground/main.dart';

void main() {
  testWidgets('playground renders the SDK test buttons', (tester) async {
    await tester.pumpWidget(const PlaygroundApp());

    expect(find.text(kWelcomeMessage), findsOneWidget);
    expect(find.text('Trigger Code Action'), findsOneWidget);
    expect(find.text('Set userId'), findsOneWidget);
    expect(find.text('Logout'), findsOneWidget);
  });

  testWidgets('tapping a not-yet-wired button shows the stub snackbar', (
    tester,
  ) async {
    await tester.pumpWidget(const PlaygroundApp());

    await tester.tap(find.text('Logout'));
    await tester.pump();

    expect(find.textContaining('not wired to the SDK yet'), findsOneWidget);
  });

  testWidgets('tapping Trigger Code Action calls the wired SDK track', (
    tester,
  ) async {
    await tester.pumpWidget(const PlaygroundApp());

    // Without APP_URL/WORKSPACE_ID the SDK is not set up, so track routes
    // through the command queue and surfaces a not_setup error — proving the
    // button is wired to the real SDK rather than the stub.
    await tester.tap(find.text('Trigger Code Action'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('not wired to the SDK yet'), findsNothing);
    expect(find.textContaining("track('code')"), findsOneWidget);
  });
}
