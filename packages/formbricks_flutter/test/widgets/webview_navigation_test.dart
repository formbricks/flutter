import 'package:flutter_test/flutter_test.dart';
import 'package:formbricks_flutter/src/widgets/webview_navigation.dart';
import 'package:url_launcher/url_launcher.dart' show LaunchMode;

void main() {
  const appUrl = 'https://app.formbricks.com';

  group('isAllowedWebViewNavigation', () {
    test('same origin → true', () {
      expect(
        isAllowedWebViewNavigation('https://app.formbricks.com/x', appUrl),
        isTrue,
      );
    });
    test('explicit default https port → true', () {
      expect(
        isAllowedWebViewNavigation(
          'https://app.formbricks.com:443/x',
          appUrl,
        ),
        isTrue,
      );
    });
    test('explicit default http port → true', () {
      expect(
        isAllowedWebViewNavigation(
          'http://localhost:80/x',
          'http://localhost',
        ),
        isTrue,
      );
    });
    test('non-default port → false', () {
      expect(
        isAllowedWebViewNavigation(
          'https://app.formbricks.com:8443/x',
          appUrl,
        ),
        isFalse,
      );
    });
    test('about:blank → true', () {
      expect(isAllowedWebViewNavigation('about:blank', appUrl), isTrue);
    });
    test('cross origin → false', () {
      expect(isAllowedWebViewNavigation('https://evil.com', appUrl), isFalse);
    });
    test('different scheme → false', () {
      expect(
        isAllowedWebViewNavigation('http://app.formbricks.com', appUrl),
        isFalse,
      );
    });
    test('unparseable candidate → false', () {
      expect(isAllowedWebViewNavigation('http://[bad', appUrl), isFalse);
    });
  });

  group('decideNavigation', () {
    test('same origin → allow', () {
      expect(
        decideNavigation(
          'https://app.formbricks.com/x',
          appUrl,
          isMainFrame: true,
        ),
        NavAction.allow,
      );
    });
    test('cross-origin main frame → open externally', () {
      expect(
        decideNavigation('https://evil.com', appUrl, isMainFrame: true),
        NavAction.openExternally,
      );
    });
    test('cross-origin sub frame → block (no external eject)', () {
      expect(
        decideNavigation('https://evil.com', appUrl, isMainFrame: false),
        NavAction.block,
      );
    });
  });

  group('openExternalUrl', () {
    test('http(s) launches with externalApplication mode', () async {
      final calls = <(Uri, LaunchMode)>[];
      Future<bool> fake(
        Uri url, {
        LaunchMode mode = LaunchMode.platformDefault,
      }) async {
        calls.add((url, mode));
        return true;
      }

      await openExternalUrl('https://x.com', launch: fake);
      expect(calls, hasLength(1));
      expect(calls.first.$1.toString(), 'https://x.com');
      expect(calls.first.$2, LaunchMode.externalApplication);
    });

    test('javascript: is blocked', () async {
      var called = false;
      Future<bool> fake(
        Uri url, {
        LaunchMode mode = LaunchMode.platformDefault,
      }) async {
        called = true;
        return true;
      }

      await openExternalUrl('javascript:alert(1)', launch: fake);
      expect(called, isFalse);
    });

    test('file:, data: and intent: are blocked', () async {
      var count = 0;
      Future<bool> fake(
        Uri url, {
        LaunchMode mode = LaunchMode.platformDefault,
      }) async {
        count++;
        return true;
      }

      await openExternalUrl('file:///etc/passwd', launch: fake);
      await openExternalUrl('data:text/html,x', launch: fake);
      await openExternalUrl('intent://scan', launch: fake);
      expect(count, 0);
    });

    test('an unparseable URL is not launched', () async {
      var called = false;
      Future<bool> fake(
        Uri url, {
        LaunchMode mode = LaunchMode.platformDefault,
      }) async {
        called = true;
        return true;
      }

      await openExternalUrl('http://[invalid', launch: fake);
      expect(called, isFalse);
    });

    test('a throwing launcher is caught (no rethrow)', () async {
      Future<bool> fake(
        Uri url, {
        LaunchMode mode = LaunchMode.platformDefault,
      }) async {
        throw Exception('boom');
      }

      await expectLater(
        openExternalUrl('https://x.com', launch: fake),
        completes,
      );
    });
  });
}
