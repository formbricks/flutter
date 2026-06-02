import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:formbricks_flutter/src/common/config.dart';
import 'package:formbricks_flutter/src/types/config.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FormbricksConfig.resetInstance();
  });

  TConfig sampleConfig({DateTime? workspaceExpiry}) => TConfig(
    workspaceId: 'wsp_1',
    appUrl: 'https://app.formbricks.com',
    workspace: TWorkspaceState(
      expiresAt: workspaceExpiry ?? DateTime(2100),
      data: const TWorkspaceData(),
    ),
    user: TUserState.defaultNoUserId,
    filteredSurveys: const [],
    status: TStatus.success,
  );

  test('update() persists and completes only after the disk write', () async {
    final config = FormbricksConfig.instance;
    await config.init();

    await config.update(sampleConfig());

    // The write has completed by the time update() returns.
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(FormbricksConfig.storageKey);
    expect(stored, isNotNull);
    expect(jsonDecode(stored!)['workspaceId'], 'wsp_1');
    expect(config.get().workspaceId, 'wsp_1');
  });

  test('reset() clears the stored entry and in-memory config', () async {
    final config = FormbricksConfig.instance;
    await config.init();
    await config.update(sampleConfig());

    await config.reset();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(FormbricksConfig.storageKey), isNull);
    expect(config.getOrNull(), isNull);
    expect(config.isInitialized, isFalse);
    expect(config.get, throwsStateError);
  });

  test('init() loads a valid cached config', () async {
    SharedPreferences.setMockInitialValues({
      FormbricksConfig.storageKey: jsonEncode(sampleConfig().toJson()),
    });
    FormbricksConfig.resetInstance();

    final config = FormbricksConfig.instance;
    await config.init();

    expect(config.isInitialized, isTrue);
    expect(config.get().workspaceId, 'wsp_1');
  });

  test('init() drops a config whose workspace has expired', () async {
    SharedPreferences.setMockInitialValues({
      FormbricksConfig.storageKey: jsonEncode(
        sampleConfig(workspaceExpiry: DateTime(2000)).toJson(),
      ),
    });
    FormbricksConfig.resetInstance();

    final config = FormbricksConfig.instance;
    await config.init();

    expect(config.getOrNull(), isNull);
  });

  test('init() keeps an error-only config (no workspace)', () async {
    SharedPreferences.setMockInitialValues({
      FormbricksConfig.storageKey: jsonEncode(
        TConfig(
          status: TStatus(value: 'error', expiresAt: DateTime(2100)),
        ).toJson(),
      ),
    });
    FormbricksConfig.resetInstance();

    final config = FormbricksConfig.instance;
    await config.init();

    expect(config.getOrNull(), isNotNull);
    expect(config.get().status.isError, isTrue);
  });

  test('get() throws before init produces a config', () {
    final config = FormbricksConfig.instance;
    expect(config.get, throwsStateError);
  });
}
