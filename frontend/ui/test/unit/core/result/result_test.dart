// Tests for `core/result/result.dart` — the `Result<T>` type every
// repository in the app returns instead of throwing. If this type's
// pattern-matching behaves incorrectly, every feature that depends on it
// silently mishandles errors, so it's worth testing in isolation.

import 'package:flutter_test/flutter_test.dart';
import 'package:phlio/core/result/result.dart';

void main() {
  group('Result.success', () {
    test('isSuccess is true, isFailure is false', () {
      const result = Result<int>.success(42);
      expect(result.isSuccess, isTrue);
      expect(result.isFailure, isFalse);
    });

    test('valueOrNull returns the wrapped value', () {
      const result = Result<String>.success('hello');
      expect(result.valueOrNull, 'hello');
    });

    test('when() calls the success branch with the value', () {
      const result = Result<int>.success(7);
      final output = result.when(
        success: (value) => 'got $value',
        failure: (_) => 'should not happen',
      );
      expect(output, 'got 7');
    });
  });

  group('Result.failure', () {
    const failure = Failure(code: 'not_found', message: 'Not found.');

    test('isFailure is true, isSuccess is false', () {
      const result = Result<int>.failure(failure);
      expect(result.isFailure, isTrue);
      expect(result.isSuccess, isFalse);
    });

    test('valueOrNull returns null', () {
      const result = Result<int>.failure(failure);
      expect(result.valueOrNull, isNull);
    });

    test('when() calls the failure branch with the Failure', () {
      const result = Result<int>.failure(failure);
      final output = result.when(
        success: (_) => 'should not happen',
        failure: (f) => 'failed: ${f.code}',
      );
      expect(output, 'failed: not_found');
    });
  });

  group('Failure', () {
    test('Failure.network() carries a network_error code', () {
      const failure = Failure.network();
      expect(failure.code, 'network_error');
      expect(failure.isUnauthorized, isFalse);
    });

    test('Failure.unknown() falls back to a default message when none given', () {
      const failure = Failure.unknown();
      expect(failure.code, 'unknown_error');
      expect(failure.message, isNotEmpty);
    });

    test('Failure.unknown(detail) uses the given detail as the message', () {
      const failure = Failure.unknown('custom detail');
      expect(failure.message, 'custom detail');
    });

    test('isUnauthorized is true only for the unauthorized code', () {
      const unauthorized = Failure(code: 'unauthorized', message: 'Please sign in again.');
      const other = Failure(code: 'not_found', message: 'Not found.');
      expect(unauthorized.isUnauthorized, isTrue);
      expect(other.isUnauthorized, isFalse);
    });
  });
}
