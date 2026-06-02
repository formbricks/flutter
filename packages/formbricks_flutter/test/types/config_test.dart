import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:formbricks_flutter/src/types/config.dart';

void main() {
  group('TConfig JSON', () {
    test('round-trips losslessly, including every DateTime field', () {
      final workspaceExpiry = DateTime(2026, 6, 1, 12, 30, 15);
      final userExpiry = DateTime(2026, 6, 1, 13);
      final displayAt = DateTime(2026, 5, 30, 9, 15);
      final lastDisplayAt = DateTime(2026, 5, 31, 10);
      final statusExpiry = DateTime(2026, 6, 1, 12, 40);

      final config = TConfig(
        workspaceId: 'wsp_1',
        appUrl: 'https://app.formbricks.com',
        workspace: TWorkspaceState(
          expiresAt: workspaceExpiry,
          data: const TWorkspaceData(
            surveys: [
              {'id': 's1'},
            ],
            actionClasses: [
              {'id': 'a1'},
            ],
            settings: {'recontactDays': 3},
          ),
        ),
        user: TUserState(
          expiresAt: userExpiry,
          data: TUserData(
            userId: 'u1',
            contactId: 'c1',
            segments: const ['seg1'],
            displays: [TDisplay(surveyId: 's1', createdAt: displayAt)],
            responses: const ['r1'],
            lastDisplayAt: lastDisplayAt,
            language: 'de',
          ),
        ),
        filteredSurveys: const [
          {'id': 's1'},
        ],
        status: TStatus(value: 'success', expiresAt: statusExpiry),
      );

      // Through a full encode → decode → parse cycle (as it hits disk).
      final decoded = TConfig.fromJson(
        jsonDecode(jsonEncode(config.toJson())) as Map<String, dynamic>,
      );

      expect(decoded.workspaceId, 'wsp_1');
      expect(decoded.appUrl, 'https://app.formbricks.com');
      expect(decoded.workspace!.expiresAt, workspaceExpiry);
      expect(decoded.workspace!.data.settings, {'recontactDays': 3});
      expect(decoded.user.expiresAt, userExpiry);
      expect(decoded.user.data.userId, 'u1');
      expect(decoded.user.data.contactId, 'c1');
      expect(decoded.user.data.segments, ['seg1']);
      expect(decoded.user.data.displays.single.surveyId, 's1');
      expect(decoded.user.data.displays.single.createdAt, displayAt);
      expect(decoded.user.data.lastDisplayAt, lastDisplayAt);
      expect(decoded.user.data.language, 'de');
      expect(decoded.filteredSurveys, [
        {'id': 's1'},
      ]);
      expect(decoded.status.value, 'success');
      expect(decoded.status.expiresAt, statusExpiry);
    });

    test('tolerates a partial payload missing workspace and user keys', () {
      final json =
          jsonDecode(
                '{"status":{"value":"error","expiresAt":"2026-06-01T12:00:00.000"}}',
              )
              as Map<String, dynamic>;

      final config = TConfig.fromJson(json);

      expect(config.workspace, isNull);
      expect(config.user.data.userId, isNull);
      expect(config.user, same(TUserState.defaultNoUserId));
      expect(config.filteredSurveys, isEmpty);
      expect(config.status.value, 'error');
      expect(config.status.isError, isTrue);
    });

    test('defaults status to success when absent', () {
      final config = TConfig.fromJson(const {});
      expect(config.status.value, 'success');
      expect(config.status.isError, isFalse);
    });
  });
}
