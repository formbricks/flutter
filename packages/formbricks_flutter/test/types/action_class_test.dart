import 'package:flutter_test/flutter_test.dart';
import 'package:formbricks_flutter/src/types/action_class.dart';

void main() {
  group('TActionClass', () {
    test('parses a code action', () {
      final a = TActionClass.fromJson({
        'id': 'a1',
        'name': 'Clicked',
        'type': 'code',
        'key': 'clicked',
      });
      expect(a.id, 'a1');
      expect(a.name, 'Clicked');
      expect(a.type, 'code');
      expect(a.key, 'clicked');
    });

    test('parses a noCode action with a null key', () {
      final a = TActionClass.fromJson({
        'id': 'a2',
        'name': 'PageView',
        'type': 'noCode',
        'key': null,
      });
      expect(a.type, 'noCode');
      expect(a.key, isNull);
    });

    test('tolerates missing optional id/type/key', () {
      final a = TActionClass.fromJson({'name': 'X'});
      expect(a.id, '');
      expect(a.type, '');
      expect(a.key, isNull);
      expect(a.name, 'X');
    });
  });
}
