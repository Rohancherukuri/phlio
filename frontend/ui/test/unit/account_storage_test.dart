import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phlio/core/storage/token_storage.dart';

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Saved accounts preserve separate tokens and logout removes only one',()async{
    FlutterSecureStorage.setMockInitialValues({});
    final storage=TokenStorage();
    await storage.saveTokens(const AuthTokens(accessToken:'a',refreshToken:'ra'));
    await storage.rememberAccount(id:'one',username:'first');
    await storage.saveTokens(const AuthTokens(accessToken:'b',refreshToken:'rb'));
    await storage.rememberAccount(id:'two',username:'second');
    var accounts=await storage.savedAccounts();
    expect(accounts.length,2);expect(accounts.first['access_token'],'a');expect(accounts.last['access_token'],'b');
    await storage.updateAccessToken('new-b');await storage.rememberAccount(id:'two',username:'second');
    accounts=await storage.savedAccounts();expect(accounts.length,2);expect(accounts.last['access_token'],'new-b');
    await storage.forgetAccount('two');await storage.clearTokens();
    expect(await storage.hasSession,false);expect((await storage.savedAccounts()).single['id'],'one');
  });
}
