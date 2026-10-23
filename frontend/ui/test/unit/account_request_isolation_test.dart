import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phlio/core/network/api_client.dart';
import 'package:phlio/core/storage/token_storage.dart';

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  test('A late 401 from the old account cannot sign out the new account',()async{
    FlutterSecureStorage.setMockInitialValues({});
    final storage=TokenStorage();
    await storage.saveTokens(const AuthTokens(accessToken:'old',refreshToken:'old-refresh'));
    var signedOut=false;
    final api=ApiClient(tokenStorage:storage,onSessionExpired:()=>signedOut=true);
    api.dio.interceptors.add(InterceptorsWrapper(onRequest:(request,handler)async{
      expect(request.headers['Authorization'],'Bearer old');
      await storage.saveTokens(const AuthTokens(accessToken:'new',refreshToken:'new-refresh'));
      handler.reject(DioException(requestOptions:request,response:Response(requestOptions:request,statusCode:401),type:DioExceptionType.badResponse),true);
    }));
    await expectLater(api.dio.get('/messaging/conversations'),throwsA(isA<DioException>()));
    expect(await storage.accessToken,'new');expect(signedOut,false);
    api.dio.close();
  });
}
