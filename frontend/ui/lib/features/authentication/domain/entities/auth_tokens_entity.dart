// Domain-level representation of an access/refresh token pair.
//
// Distinct from `core/storage/token_storage.dart`'s `AuthTokens` on
// purpose: that one is an infrastructure detail (what secure storage
// persists), this one is what the domain/use-case layer works with. They
// happen to look identical today; keeping them separate means a future
// change to one (e.g. adding token scopes to the domain entity) doesn't
// ripple into the other.

class AuthTokensEntity {
  const AuthTokensEntity({required this.accessToken, required this.refreshToken});

  final String accessToken;
  final String refreshToken;
}
