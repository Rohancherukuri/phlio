import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phlio/app/theme/app_theme.dart';
import 'package:phlio/core/result/result.dart';
import 'package:phlio/design_system/widgets/phlio_text_field.dart';
import 'package:phlio/features/authentication/domain/entities/user_entity.dart';
import 'package:phlio/features/authentication/presentation/controllers/auth_controller.dart';
import 'package:phlio/features/authentication/presentation/screens/signup_screen.dart';
import 'package:phlio/features/authentication/presentation/screens/login_screen.dart';

class _Auth extends AuthController {
  String? birthday;
  String? phone;
  @override
  Future<UserEntity?> build() async => null;
  @override
  Future<Result<UserEntity>> register(
      {required String fullName,
      required String username,
      required String email,
      required String password,
      required List<String> interests,
      String? dateOfBirth,
      String? phoneNumber}) async {
    birthday = dateOfBirth;
    phone = phoneNumber;
    return const Result.failure(
        Failure(code: 'test', message: 'Submission captured'));
  }
}

Finder field(String label) => find.descendant(
    of: find.byWidgetPredicate(
        (w) => w is PhlioTextField && w.semanticLabel == label),
    matching: find.byType(TextFormField));

void main() {
  if (const bool.fromEnvironment('CAPTURE_AUTH')) {
    testWidgets('Capture account screens', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final family in ['Manrope', 'Quicksand']) {
        final loader = FontLoader(family);
        final base = family == 'Manrope' ? 'manrope-v20' : 'quicksand-v37';
        for (final weight in ['regular', '500', '600', '700']) {
          loader
              .addFont(rootBundle.load('assets/fonts/$base-latin-$weight.ttf'));
        }
        await loader.load();
      }
      await (FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
          .load();
      for (final screen in [const LoginScreen(), const SignupScreen()]) {
        final key = GlobalKey();
        await tester.pumpWidget(ProviderScope(
            overrides: [authControllerProvider.overrideWith(_Auth.new)],
            child: RepaintBoundary(
                key: key,
                child: MaterialApp(
                    debugShowCheckedModeBanner: false,
                    theme: AppTheme.dark,
                    home: screen))));
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 500)));
        await tester.pump(const Duration(milliseconds: 100));
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          Directory('build/account-previews').createSync(recursive: true);
          File('build/account-previews/${screen.runtimeType}.png')
              .writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }

  testWidgets('Signup requires private details and sends normalized values',
      (tester) async {
    final auth = _Auth();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(overrides: [
      authControllerProvider.overrideWith(() => auth),
    ], child: MaterialApp(theme: AppTheme.dark, home: const SignupScreen())));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    for (final entry in {
      'Full name': 'Test User',
      'Username': 'testuser',
      'Email': 'test@example.com',
      'Password': 'password123'
    }.entries) {
      await tester.ensureVisible(field(entry.key));
      await tester.enterText(field(entry.key), entry.value);
    }
    await tester.ensureVisible(find.text('Continue'));
    await tester.tap(find.text('Continue'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.text('Choose your date of birth'), findsOneWidget);
    expect(find.textContaining('Include your country code'), findsOneWidget);
    await tester.ensureVisible(field('Phone number with country code'));
    await tester.enterText(
        field('Phone number with country code'), '+91 (98765) 43210');
    await tester.ensureVisible(field('Date of birth'));
    await tester.tap(field('Date of birth'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    final shownBirthday =
        tester.widget<TextFormField>(field('Date of birth')).controller!.text;
    expect(shownBirthday, isNotEmpty);
    await tester.ensureVisible(find.text('Continue'));
    await tester.tap(find.text('Continue'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.text('Step 2 of 2'), findsOneWidget);
    await tester.ensureVisible(find.text('Continue'));
    await tester.tap(find.text('Continue'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(auth.phone, '+919876543210');
    expect(DateTime.parse(auth.birthday!).year, DateTime.now().year - 18);
    expect(tester.takeException(), isNull);
  });

  for (final screen in [const LoginScreen(), const SignupScreen()]) {
    testWidgets('${screen.runtimeType} fits narrow screens with large text',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(ProviderScope(
          overrides: [authControllerProvider.overrideWith(_Auth.new)],
          child: MaterialApp(
              theme: AppTheme.dark,
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: const TextScaler.linear(2)),
                  child: child!),
              home: screen)));
      await tester.pump(const Duration(seconds: 1));
      final scroll = find.byType(Scrollable).first;
      tester.state<ScrollableState>(scroll).position.jumpTo(
          tester.state<ScrollableState>(scroll).position.maxScrollExtent);
      await tester.pump();
      expect(find.text('PEOPLE    PLACES    POSSIBILITIES'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
