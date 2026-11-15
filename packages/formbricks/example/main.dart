// A minimal app that uses the Formbricks SDK. For a full demo app, see
// apps/playground in https://github.com/formbricks/flutter.
import 'package:flutter/material.dart';
import 'package:formbricks/formbricks.dart';

void main() => runApp(const ExampleApp());

/// Mounts the [Formbricks] host widget once, next to the app's content.
class ExampleApp extends StatelessWidget {
  /// Creates the example app.
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Stack(
        children: [
          HomePage(),
          // Sets up the SDK and renders triggered surveys in an overlay.
          Formbricks(
            appUrl: 'https://app.formbricks.com',
            workspaceId: 'your-workspace-id',
          ),
        ],
      ),
    );
  }
}

/// Identifies the user and tracks an action that can trigger a survey.
class HomePage extends StatelessWidget {
  /// Creates the home page.
  const HomePage({super.key});

  Future<void> _onCheckout() async {
    await Formbricks.setUserId('user_123');
    await Formbricks.setAttribute('plan', 'pro');
    final result = await Formbricks.track('checkout_completed');
    if (result case Err(:final error)) {
      debugPrint('Formbricks: ${error.message}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: _onCheckout,
          child: const Text('Complete checkout'),
        ),
      ),
    );
  }
}
