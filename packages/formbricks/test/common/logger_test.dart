import 'package:flutter_test/flutter_test.dart';
import 'package:formbricks/src/common/logger.dart';

void main() {
  setUp(Logger.resetInstance);

  test('defaults to error level', () {
    expect(Logger.level, LogLevel.error);
  });

  test('configure sets the level', () {
    Logger.configure(level: LogLevel.debug);
    expect(Logger.level, LogLevel.debug);
  });

  test('configure(null) leaves the level unchanged', () {
    Logger.configure(level: LogLevel.debug);
    Logger.configure();
    expect(Logger.level, LogLevel.debug);
  });

  test('resetInstance restores the default level', () {
    Logger.configure(level: LogLevel.debug);
    Logger.resetInstance();
    expect(Logger.level, LogLevel.error);
  });

  test('debug and error do not throw at any level', () {
    Logger.configure(level: LogLevel.error);
    expect(() => Logger.debug('suppressed'), returnsNormally);
    expect(() => Logger.error('emitted'), returnsNormally);
  });
}
