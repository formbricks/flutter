import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:formbricks_flutter/formbricks_flutter.dart';
import 'package:formbricks_flutter/src/common/config.dart';
import 'package:formbricks_flutter/src/common/setup.dart';
import 'package:formbricks_flutter/src/types/config.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FormbricksConfig.resetInstance();
    resetSetupForTest();
  });

  test(
    'Formbricks.setup routes through the queue and validates input',
    () async {
      // Missing workspaceId fails validation before any network call, so this
      // exercises the public facade → command queue → setup path end-to-end.
      final result = await Formbricks.setup(
        appUrl: 'https://app.x',
        workspaceId: '',
      );

      expect(result.isErr, isTrue);
      final error = switch (result) {
        Ok() => fail('expected Err'),
        Err(:final error) => error,
      };
      expect(error, isA<MissingFieldError>());
    },
  );

  test(
    'debugStoredConfig returns null when empty, raw JSON after a write',
    () async {
      expect(await Formbricks.debugStoredConfig(), isNull);

      final config = FormbricksConfig.instance;
      await config.init();
      await config.update(const TConfig(workspaceId: 'w', appUrl: 'https://x'));

      final raw = await Formbricks.debugStoredConfig();
      expect(raw, isNotNull);
      expect(jsonDecode(raw!)['workspaceId'], 'w');
    },
  );
}
