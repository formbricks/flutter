import 'package:flutter/material.dart';
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

  testWidgets('shows editable App URL / Workspace ID connection fields', (
    tester,
  ) async {
    await tester.pumpWidget(const PlaygroundApp());

    expect(find.widgetWithText(TextField, 'App URL'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Workspace ID'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
    // Not connected without --dart-define credentials.
    expect(find.textContaining('not connected'), findsOneWidget);
  });

  testWidgets('Connect with empty fields prompts for credentials', (
    tester,
  ) async {
    await tester.pumpWidget(const PlaygroundApp());

    await tester.tap(find.text('Connect'));
    await tester.pump();

    expect(
      find.textContaining('Enter an App URL and Workspace ID'),
      findsOneWidget,
    );
  });

  testWidgets('identity buttons are disabled until connected', (tester) async {
    await tester.pumpWidget(const PlaygroundApp());

    final logoutButton = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Logout'),
        matching: find.byType(FilledButton),
      ),
    );
    // Not connected (no --dart-define credentials) → command would throw
    // NotSetupError, so the button is gated off.
    expect(logoutButton.onPressed, isNull);
  });

  testWidgets('local storage buttons render and are always enabled', (
    tester,
  ) async {
    await tester.pumpWidget(const PlaygroundApp());

    for (final label in ['Log Local Storage', 'Clear Local Storage']) {
      final button = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text(label),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(button.onPressed, isNotNull);
    }
  });

  testWidgets('tapping Trigger Code Action calls the wired SDK track', (
    tester,
  ) async {
    await tester.pumpWidget(const PlaygroundApp());

    await tester.tap(find.text('Trigger Code Action'));
    await tester.pumpAndSettle();

    expect(find.textContaining('not wired to the SDK yet'), findsNothing);
    expect(find.textContaining("track('code')"), findsWidgets);
  });
}
