import 'package:flutter/material.dart';
import 'package:formbricks_flutter/formbricks_flutter.dart';

/// Credentials are injected at build time, mirroring the React Native
/// playground's use of `EXPO_PUBLIC_*` env vars. Pass them with:
///   --dart-define=APP_URL=https://app.formbricks.com --dart-define=WORKSPACE_ID=wsp_...
const String _appUrl = String.fromEnvironment('APP_URL');
const String _workspaceId = String.fromEnvironment('WORKSPACE_ID');

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

class PlaygroundHome extends StatefulWidget {
  const PlaygroundHome({super.key});

  @override
  State<PlaygroundHome> createState() => _PlaygroundHomeState();
}

class _PlaygroundHomeState extends State<PlaygroundHome> {
  String _status = 'initializing…';

  @override
  void initState() {
    super.initState();
    _initFormbricks();
  }

  Future<void> _initFormbricks() async {
    if (_appUrl.isEmpty || _workspaceId.isEmpty) {
      setState(
        () => _status =
            'Missing APP_URL / WORKSPACE_ID — pass them via --dart-define',
      );
      return;
    }
    try {
      final result = await Formbricks.setup(
        appUrl: _appUrl,
        workspaceId: _workspaceId,
        logLevel: LogLevel.debug,
      );
      if (!mounted) return;
      setState(() {
        _status = switch (result) {
          Ok() => 'setup complete ✓',
          Err(:final error) => 'setup error: ${error.message}',
        };
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'setup failed: $e');
    }
  }

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
              const Text('Welcome to Formbricks', textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                'setup: $_status',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 12),
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
