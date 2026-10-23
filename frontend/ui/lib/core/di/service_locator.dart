// Dependency injection composition root (get_it).
//
// This is the one file in the whole app allowed to import a `*RepositoryImpl`
// or `*RemoteDataSource` directly — everywhere else (controllers, use
// cases, widgets) depends on the `abstract interface class` from each
// feature's `domain/repositories/`. `setupServiceLocator()` is called once
// in `main.dart` before `runApp`.
//
// Why `get_it` alongside Riverpod rather than Riverpod for everything?
// `get_it` owns plain, non-reactive singletons (the `Dio`-backed data
// sources and repositories — infrastructure, not UI state); Riverpod owns
// everything that's actually reactive (controllers, `AsyncNotifier`s).
// Mixing the two this way avoids re-registering the same repository
// construction logic as a `Provider` in every feature.

import 'package:get_it/get_it.dart';

import '../../features/activity/data/datasources/activity_remote_datasource.dart';
import '../../features/activity/data/repositories/activity_repository_impl.dart';
import '../../features/activity/domain/repositories/activity_repository.dart';
import '../../features/authentication/data/datasources/auth_remote_datasource.dart';
import '../../features/authentication/data/repositories/auth_repository_impl.dart';
import '../../features/authentication/domain/repositories/auth_repository.dart';
import '../../features/book/data/datasources/book_remote_datasource.dart';
import '../../features/book/data/repositories/book_repository_impl.dart';
import '../../features/book/domain/repositories/book_repository.dart';
import '../../features/home/data/datasources/home_remote_datasource.dart';
import '../../features/home/data/repositories/home_repository_impl.dart';
import '../../features/home/domain/repositories/home_repository.dart';
import '../../features/pay/data/datasources/pay_remote_datasource.dart';
import '../../features/pay/data/repositories/pay_repository_impl.dart';
import '../../features/pay/domain/repositories/pay_repository.dart';
import '../../features/phlio_agent/data/datasources/agent_remote_datasource.dart';
import '../../features/phlio_agent/data/repositories/agent_repository_impl.dart';
import '../../features/phlio_agent/domain/repositories/agent_repository.dart';
import '../../features/rooms/data/datasources/rooms_remote_datasource.dart';
import '../../features/rooms/data/repositories/rooms_repository_impl.dart';
import '../../features/rooms/domain/repositories/rooms_repository.dart';
import '../../features/shop/data/datasources/shop_remote_datasource.dart';
import '../../features/shop/data/repositories/shop_repository_impl.dart';
import '../../features/shop/domain/repositories/shop_repository.dart';
import '../../features/social/data/datasources/social_remote_datasource.dart';
import '../../features/social/data/repositories/social_repository_impl.dart';
import '../../features/social/domain/repositories/social_repository.dart';
import '../logging/app_logger.dart';
import '../network/api_client.dart';
import '../storage/token_storage.dart';

final _logger = createLogger('phlio.di');

final GetIt getIt = GetIt.instance;

/// Registers every singleton the app needs. Idempotent-safe to call once;
/// calling it twice (e.g. in a hot-restart during development) would throw
/// from `get_it`, which is a deliberate signal to fix the call site rather
/// than something to silently swallow.
void setupServiceLocator() {
  // -- Core infrastructure -------------------------------------------------
  getIt.registerLazySingleton<TokenStorage>(() => TokenStorage());
  getIt.registerLazySingleton<ApiClient>(
    () => ApiClient(tokenStorage: getIt<TokenStorage>()),
  );

  // -- Authentication ---------------------------------------------------------
  getIt.registerLazySingleton<AuthRemoteDataSource>(() => AuthRemoteDataSource(getIt<ApiClient>()));
  getIt.registerLazySingleton<AuthRepository>(
    () => AuthRepositoryImpl(
      remoteDataSource: getIt<AuthRemoteDataSource>(),
      tokenStorage: getIt<TokenStorage>(),
    ),
  );

  // -- Social -----------------------------------------------------------------
  getIt.registerLazySingleton<SocialRemoteDataSource>(() => SocialRemoteDataSource(getIt<ApiClient>()));
  getIt.registerLazySingleton<SocialRepository>(
    () => SocialRepositoryImpl(getIt<SocialRemoteDataSource>()),
  );

  // -- Rooms ------------------------------------------------------------------
  getIt.registerLazySingleton<RoomsRemoteDataSource>(() => RoomsRemoteDataSource(getIt<ApiClient>()));
  getIt.registerLazySingleton<RoomsRepository>(
    () => RoomsRepositoryImpl(getIt<RoomsRemoteDataSource>()),
  );

  // -- Shop ----------------------------------------------------------------------
  getIt.registerLazySingleton<ShopRemoteDataSource>(() => ShopRemoteDataSource(getIt<ApiClient>()));
  getIt.registerLazySingleton<ShopRepository>(() => ShopRepositoryImpl(getIt<ShopRemoteDataSource>()));

  // -- Phlio Agent ----------------------------------------------------------
  getIt.registerLazySingleton<AgentRemoteDataSource>(() => AgentRemoteDataSource(getIt<ApiClient>()));
  getIt.registerLazySingleton<AgentRepository>(
    () => AgentRepositoryImpl(getIt<AgentRemoteDataSource>()),
  );

  // -- Home (aggregates the above) ---------------------------------------
  getIt.registerLazySingleton<HomeRemoteDataSource>(() => HomeRemoteDataSource(getIt<ApiClient>()));
  getIt.registerLazySingleton<HomeRepository>(() => HomeRepositoryImpl(getIt<HomeRemoteDataSource>()));

  // -- Book ------------------------------------------------------------------
  getIt.registerLazySingleton<BookRemoteDataSource>(() => BookRemoteDataSource(getIt<ApiClient>()));
  getIt.registerLazySingleton<BookRepository>(() => BookRepositoryImpl(getIt<BookRemoteDataSource>()));

  // -- Pay ---------------------------------------------------------------------
  getIt.registerLazySingleton<PayRemoteDataSource>(() => PayRemoteDataSource(getIt<ApiClient>()));
  getIt.registerLazySingleton<PayRepository>(() => PayRepositoryImpl(getIt<PayRemoteDataSource>()));

  // -- Activity (cross-domain feed) ----------------------------------------
  getIt.registerLazySingleton<ActivityRemoteDataSource>(
    () => ActivityRemoteDataSource(getIt<ApiClient>()),
  );
  getIt.registerLazySingleton<ActivityRepository>(
    () => ActivityRepositoryImpl(getIt<ActivityRemoteDataSource>()),
  );

  _logger.info('Service locator ready — all repositories registered.');
}
