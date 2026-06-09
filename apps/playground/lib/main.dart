import 'package:flutter/material.dart';
import 'package:formbricks_flutter/formbricks_flutter.dart';

const String _defaultAppUrl = String.fromEnvironment('APP_URL');
const String _defaultWorkspaceId = String.fromEnvironment('WORKSPACE_ID');

const String kWelcomeMessage = 'Welcome to Formbricks';
const String _statusConnected = 'connected ✓';

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

  final TextEditingController _codeController = TextEditingController(
    text: 'code',
  );

  String _status = 'not connected';
  bool _connected = false;
  String? _connectedAppUrl;
  String? _connectedWorkspaceId;

  String? _lastTrack;

  @override
  void initState() {
    super.initState();
    // Auto-connect when both values were provided via --dart-define.
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

    // setup() is idempotent and there is no public teardown yet, so switching
    // to a different workspace mid-session cannot take effect.
    if (_connected &&
        (appUrl != _connectedAppUrl || workspaceId != _connectedWorkspaceId)) {
      setState(
        () => _status =
            'Already connected to "$_connectedWorkspaceId". Restart the app '
            'to switch workspace.',
      );
      return;
    }

    setState(() => _status = 'connecting...');
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
            _status = _statusConnected;
          case Err(:final error):
            _status = 'setup error: ${error.code.wire}: ${error.message}';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'setup failed: $e');
    }
  }

  Future<void> _track(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final code = _codeController.text.trim().isEmpty
        ? 'code'
        : _codeController.text.trim();
    String message;
    try {
      final result = await Formbricks.track(code);
      message = switch (result) {
        Ok() => "track('$code') -> ok - a matching survey may show",
        Err(:final error) =>
          "track('$code') -> ${error.code.wire}: ${error.message}",
      };
    } on FormbricksError catch (e) {
      message = "track('$code') -> ${e.code.wire}: ${e.message}";
    }
    if (!mounted) return;
    setState(() => _lastTrack = message);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
      );
  }

  /// Runs an identity command and reports the result in a snackbar.
  ///
  /// The user-update queue debounces the backend call ~500 ms after the last
  /// identity/attribute change, so an `ok` here means the command was accepted,
  /// not that the network round-trip has finished.
  Future<void> _runAction(
    BuildContext context,
    String action,
    Future<Result<void, FormbricksError>> Function() op,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    String message;
    try {
      final result = await op();
      message = switch (result) {
        Ok() => '$action -> ok',
        Err(:final error) => '$action -> ${error.code.wire}: ${error.message}',
      };
    } on FormbricksError catch (e) {
      message = '$action -> ${e.code.wire}: ${e.message}';
    }
    if (!mounted) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
      );
  }

  /// Reads the persisted config and dumps it to the console.
  Future<void> _logStorage(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final raw = await Formbricks.debugStoredConfig();
    debugPrint('Formbricks local storage: ${raw ?? '<empty>'}');
    if (!mounted) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            raw == null
                ? 'local storage is empty'
                : 'local storage logged to console (${raw.length} chars)',
          ),
        ),
      );
  }

  /// Clears the persisted config + in-memory copy.
  Future<void> _clearStorage(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    await Formbricks.debugClearStoredConfig();
    if (!mounted) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('local storage cleared')),
      );
  }

  @override
  Widget build(BuildContext context) {
    final identityActions =
        <({String label, String action, Future<Result<void, FormbricksError>> Function() op})>[
      (
        label: 'Set userId',
        action: "setUserId('playground-user')",
        op: () => Formbricks.setUserId('playground-user'),
      ),
      (
        label: 'Set User Attributes (multiple)',
        action: 'setAttributes({plan, mrr, signup_date})',
        op: () => Formbricks.setAttributes({
          'plan': 'pro',
          'mrr': 99,
          'signup_date': DateTime.now(),
        }),
      ),
      (
        label: 'Set User Attribute (single)',
        action: "setAttribute('source', 'playground')",
        op: () => Formbricks.setAttribute('source', 'playground'),
      ),
      (
        label: 'Set Language (de)',
        action: "setLanguage('de')",
        op: () => Formbricks.setLanguage('de'),
      ),
      (
        label: 'Logout',
        action: 'logout()',
        op: Formbricks.logout,
      ),
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
                    hintText: 'wsp_...',
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
                if (_connected && _status != _statusConnected) ...[
                  const SizedBox(height: 4),
                  Text(
                    _status,
                    textAlign: TextAlign.center,
                    style: textTheme.bodySmall,
                  ),
                ],
                const Divider(height: 40),

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

                for (final a in identityActions) ...[
                  FilledButton.tonal(
                    onPressed: _connected
                        ? () => _runAction(context, a.action, a.op)
                        : null,
                    child: Text(a.label),
                  ),
                  const SizedBox(height: 12),
                ],

                const Divider(height: 40),
                Text('Local storage', style: textTheme.titleSmall),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => _logStorage(context),
                  child: const Text('Log Local Storage'),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => _clearStorage(context),
                  child: const Text('Clear Local Storage'),
                ),
                const SizedBox(height: 12),

                // Mounted once connected so triggered surveys can render
                // against the connected workspace.
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
