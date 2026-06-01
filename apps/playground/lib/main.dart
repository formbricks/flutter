import 'package:flutter/material.dart';
import 'package:formbricks_flutter/formbricks_flutter.dart';

void main() {
  runApp(const PlaygroundApp());
}

class PlaygroundApp extends StatelessWidget {
  const PlaygroundApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Formbricks Flutter Playground',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const PlaygroundHome(),
    );
  }
}

class PlaygroundHome extends StatelessWidget {
  const PlaygroundHome({super.key});

  /// Stub for SDK calls. The real `Formbricks.*` API is not wired yet.
  /// For now each button just confirms the tap so the demo's UX can be
  /// exercised independently of the SDK.
  void _stub(BuildContext context, String action) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('$action — not wired to the SDK yet'),
          duration: const Duration(seconds: 1),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    // Proves the SDK package links into the app via the pub workspace.
    final greeting = welcome();

    final actions = <({String label, String action})>[
      (label: 'Trigger Code Action', action: "track('code')"),
      (label: 'Set userId', action: "setUserId('random-user-id')"),
      (label: 'Set User Attributes (multiple)', action: 'setAttributes({...})'),
      (label: 'Set User Attribute (single)', action: "setAttribute('k', 'v')"),
      (label: 'Set Language (de)', action: "setLanguage('de')"),
      (label: 'Logout', action: 'logout()'),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Formbricks Flutter Playground')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(greeting, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              for (final a in actions) ...[
                FilledButton(
                  onPressed: () => _stub(context, a.action),
                  child: Text(a.label),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
