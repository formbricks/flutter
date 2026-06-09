import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:formbricks_flutter/src/widgets/default_webview_host.dart';

void main() {
  // Regression guard for the "survey closes/reloads when you tap an input" bug:
  // the soft keyboard changes MediaQuery.viewInsets, which rebuilds the
  // keyboard-avoiding padding around the host. The host MUST be a StatefulWidget
  // that creates its WebViewController once in initState — if it ever regresses
  // to a StatelessWidget (or creates the controller in build()), the controller
  // is recreated and the survey reloads on every keystroke.
  //
  // Constructing the widget does NOT touch a platform channel: the controller is
  // only created in initState, which runs when the widget is mounted (it is not
  // here), so this is safe to run under `flutter test`.
  testWidgets(
    'defaultWebViewHost returns a StatefulWidget so its controller survives '
    'rebuilds',
    (tester) async {
      late Widget host;
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            host = defaultWebViewHost(
              context,
              html: '<html></html>',
              appUrl: 'https://app.formbricks.com',
              onEvent: (_) {},
            );
            return const SizedBox();
          },
        ),
      );

      expect(host, isA<StatefulWidget>());
    },
  );
}
