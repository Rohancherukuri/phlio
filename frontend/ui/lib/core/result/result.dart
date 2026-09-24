// A small `Result<T>` type used at the domain/repository boundary.
//
// Repositories return `Result<T>` rather than throwing, so a controller
// can handle "no internet" or "validation failed" as ordinary data instead
// of a try/catch around every call. Modeled as a sealed class so the
// compiler forces every consumer to handle both cases (exhaustive `switch`),
// which is the whole point versus a nullable value or a bare exception.

sealed class Result<T> {
  const Result();

  const factory Result.success(T value) = Success<T>;
  const factory Result.failure(Failure failure) = ResultFailure<T>;

  bool get isSuccess => this is Success<T>;
  bool get isFailure => this is ResultFailure<T>;

  /// Returns the success value, or `null` if this is a failure.
  T? get valueOrNull => switch (this) {
        Success<T>(:final value) => value,
        ResultFailure<T>() => null,
      };

  /// Pattern-matches on the result, forcing both branches to be handled.
  R when<R>({
    required R Function(T value) success,
    required R Function(Failure failure) failure,
  }) {
    return switch (this) {
      Success<T>(:final value) => success(value),
      ResultFailure<T>(:final error) => failure(error),
    };
  }
}

final class Success<T> extends Result<T> {
  const Success(this.value);
  final T value;
}

final class ResultFailure<T> extends Result<T> {
  const ResultFailure(this.error);
  final Failure error;
}

/// A domain-level failure — the Flutter-side mirror of the backend's
/// `AppError` envelope (`code` + `message`), plus a `network` case for
/// connectivity problems the backend never gets to weigh in on.
class Failure {
  const Failure({required this.code, required this.message});

  const Failure.network() : code = 'network_error', message = 'Check your connection and try again.';

  const Failure.unknown([String? detail])
      : code = 'unknown_error',
        message = detail ?? 'Something went wrong. Please try again.';

  final String code;
  final String message;

  bool get isUnauthorized => code == 'unauthorized';

  @override
  String toString() => 'Failure($code: $message)';
}
