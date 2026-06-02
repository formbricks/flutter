import 'package:flutter_test/flutter_test.dart';
import 'package:formbricks_flutter/src/types/errors.dart';

void main() {
  test('error codes expose their wire strings', () {
    expect(FormbricksErrorCode.missingField.wire, 'missing_field');
    expect(FormbricksErrorCode.networkError.wire, 'network_error');
    expect(FormbricksErrorCode.notSetup.wire, 'not_setup');
    expect(FormbricksErrorCode.forbidden.wire, 'forbidden');
    expect(FormbricksErrorCode.invalidCode.wire, 'invalid_code');
  });

  test('MissingFieldError defaults and overrides its message', () {
    final error = MissingFieldError('appUrl');
    expect(error.field, 'appUrl');
    expect(error.code, FormbricksErrorCode.missingField);
    expect(error.message, 'No appUrl provided');
    expect(error.toString(), contains('missing_field'));
    expect(MissingFieldError('x', message: 'custom').message, 'custom');
  });

  test('NotSetupError has a default message', () {
    final error = NotSetupError();
    expect(error.code, FormbricksErrorCode.notSetup);
    expect(error.message, contains('not set up'));
  });

  test('NetworkError carries status, url and responseMessage', () {
    final error = NetworkError(
      message: 'm',
      status: 500,
      url: Uri.parse('https://x'),
      responseMessage: 'r',
    );
    expect(error.code, FormbricksErrorCode.networkError);
    expect(error.status, 500);
    expect(error.url, Uri.parse('https://x'));
    expect(error.responseMessage, 'r');
  });

  test('InvalidCodeError uses the invalid_code code', () {
    expect(InvalidCodeError().code, FormbricksErrorCode.invalidCode);
  });

  test(
    'FormbricksSetupError defaults to network_error and accepts forbidden',
    () {
      expect(FormbricksSetupError().code, FormbricksErrorCode.networkError);
      expect(
        FormbricksSetupError(code: FormbricksErrorCode.forbidden).code,
        FormbricksErrorCode.forbidden,
      );
    },
  );

  test('ApiErrorResponse exposes its fields and toString', () {
    const error = ApiErrorResponse(
      code: 'forbidden',
      status: 403,
      message: 'no',
    );
    expect(error.code, 'forbidden');
    expect(error.status, 403);
    expect(error.toString(), contains('forbidden'));
  });
}
