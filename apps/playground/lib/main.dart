import 'package:flutter/material.dart';
import 'package:formbricks_flutter/formbricks_flutter.dart';

/// Default credentials, injected at build time, mirroring the React Native
/// playground's use of `EXPO_PUBLIC_*` env vars. Pass them via `--dart-define`
/// (or a local `apps/playground/.env`, which `tool/run.sh` forwards):
///   --dart-define=APP_URL=https://app.formbricks.com --dart-define=WORKSPACE_ID=wsp_...
/// They only pre-fill the connection fields below — you can also type them in
/// at runtime and tap Connect.
const String _defaultAppUrl = String.fromEnvironment('APP_URL');
const String _defaultWorkspaceId = String.fromEnvironment('WORKSPACE_ID');

/// Header text. Also referenced by the widget test.
const String kWelcomeMessage = 'Welcome to Formbricks';

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
  final TextEditingController _appUrlController = TextEditingController(
    text: _defaultAppUrl,
  );
  final TextEditingController _workspaceIdController = TextEditingController(
    text: _defaultWorkspaceId,
  );

  /// The code action to trigger. Editable so the demo can match whatever code
  /// action exists in the connected workspace.
  final TextEditingController _codeController = TextEditingController(
    text: 'code',
  );

  String _status = 'not connected';
  bool _connected = false;
  String? _connectedAppUrl;
  String? _connectedWorkspaceId;

  /// The last `track(...)` outcome, shown persistently (the snackbar fades).
  String? _lastTrack;

  @override
  void initState() {
    super.initState();
    // Zero-friction path: auto-connect when both were provided via --dart-define.
    if (_defaultAppUrl.isNotEmpty && _defaultWorkspaceId.isNotEmpty) {
      _connect();
    }
  }

  @override
  void dispose() {
    _appUrlController.dispose();
    _workspaceIdController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final appUrl = _appUrlController.text.trim();
    final workspaceId = _workspaceIdController.text.trim();

    if (appUrl.isEmpty || workspaceId.isEmpty) {
      setState(
        () => _status = 'Enter an App URL and Workspace ID, then Connect.',
      );
      return;
    }

    // setup() is idempotent and there is no public teardown yet (logout is a
    // later ticket), so switching to a different workspace mid-session can't
    // take effect — be honest about it rather than silently no-op.
    if (_connected &&
        (appUrl != _connectedAppUrl || workspaceId != _connectedWorkspaceId)) {
      setState(
        () => _status =
            'Already connected to "$_connectedWorkspaceId". Restart the app '
            'to switch workspace.',
      );
      return;
    }

    setState(() => _status = 'connecting…');
    try {
      final result = await Formbricks.setup(
        appUrl: appUrl,
        workspaceId: workspaceId,
        logLevel: LogLevel.debug,
      );
      if (!mounted) return;
      setState(() {
        switch (result) {
          case Ok():
            _connected = true;
            _connectedAppUrl = appUrl;
            _connectedWorkspaceId = workspaceId;
            _status = 'connected ✓';
          case Err(:final error):
            _status = 'setup error: ${error.code.wire}: ${error.message}';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'setup failed: $e');
    }
  }

  /// Tracks the entered code action through the SDK and reports the Result.
  ///
  /// On `ok` with a matching live survey, the [Formbricks] widget below renders
  /// it in a modal WebView. On `invalid_code` the action doesn't exist in the
  /// workspace; on `network_error` the device is offline.
  Future<void> _track(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final code = _codeController.text.trim().isEmpty
        ? 'code'
        : _codeController.text.trim();
    String message;
    try {
      final result = await Formbricks.track(code);
      message = switch (result) {
        Ok() => "track('$code') → ok — a matching survey (if any) will show",
        Err(:final error) =>
          "track('$code') → ${error.code.wire}: ${error.message}",
      };
    } on FormbricksError catch (e) {
      // e.g. not_setup when you haven't connected yet.
      message = "track('$code') → ${e.code.wire}: ${e.message}";
    }
    if (!mounted) return;
    setState(() => _lastTrack = message);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
      );
  }

  /// Stub for the SDK calls whose tickets aren't landed yet (identify /
  /// attributes / language / logout). Confirms the tap so the demo UX can be
  /// exercised independently of those features.
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
    final stubActions = <({String label, String action})>[
      (label: 'Set userId', action: "setUserId('random-user-id')"),
      (label: 'Set User Attributes (multiple)', action: 'setAttributes({...})'),
      (label: 'Set User Attribute (single)', action: "setAttribute('k', 'v')"),
      (label: 'Set Language (de)', action: "setLanguage('de')"),
      (label: 'Logout', action: 'logout()'),
    ];
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Formbricks Flutter Playground')),
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(kWelcomeMessage, textAlign: TextAlign.center),
                const SizedBox(height: 16),

                // --- Connection --------------------------------------------
                Text('Connection', style: textTheme.titleSmall),
                const SizedBox(height: 8),
                TextField(
                  controller: _appUrlController,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'App URL',
                    hintText: 'https://app.formbricks.com',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _workspaceIdController,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Workspace ID',
                    hintText: 'wsp_…',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _connect,
                  child: Text(_connected ? 'Reconnect' : 'Connect'),
                ),
                const SizedBox(height: 8),
                Text(
                  _connected
                      ? 'Connected to $_connectedWorkspaceId @ $_connectedAppUrl'
                      : 'status: $_status',
                  textAlign: TextAlign.center,
                  style: textTheme.bodySmall,
                ),
                if (_connected && _status != 'connected ✓') ...[
                  const SizedBox(height: 4),
                  Text(
                    _status,
                    textAlign: TextAlign.center,
                    style: textTheme.bodySmall,
                  ),
                ],
                const Divider(height: 40),

                // --- Track a code action -----------------------------------
                Text('Track a code action', style: textTheme.titleSmall),
                const SizedBox(height: 8),
                TextField(
                  controller: _codeController,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Code action key',
                    helperText:
                        'Must match a code action that triggers a live survey',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => _track(context),
                  child: const Text('Trigger Code Action'),
                ),
                if (_lastTrack != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _lastTrack!,
                    textAlign: TextAlign.center,
                    style: textTheme.bodySmall,
                  ),
                ],
                const Divider(height: 40),

                // --- Not-yet-wired actions ---------------------------------
                for (final a in stubActions) ...[
                  FilledButton.tonal(
                    onPressed: () => _stub(context, a.action),
                    child: Text(a.label),
                  ),
                  const SizedBox(height: 12),
                ],

                // Host the SDK widget so a triggered survey can render. It is
                // zero-size while idle and pushes a modal route when a survey is
                // active; mounted once connected so it renders against the
                // connected workspace.
                if (_connected)
                  Formbricks(
                    appUrl: _connectedAppUrl!,
                    workspaceId: _connectedWorkspaceId!,
                    logLevel: LogLevel.debug,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
