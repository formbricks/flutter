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

  testWidgets('tapping a button shows a not-wired snackbar', (tester) async {
    await tester.pumpWidget(const PlaygroundApp());

    await tester.tap(find.text('Trigger Code Action'));
    await tester.pump();

    expect(find.textContaining('not wired to the SDK yet'), findsOneWidget);
  });
}
