import 'package:appsocial/core/theme/app_colors.dart';
import 'package:appsocial/core/theme/theme_controller.dart';
import 'package:appsocial/core/utils/validators.dart';
import 'package:appsocial/presentation/screens/forgot_password_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('validateEmail rejects empty and malformed addresses', () {
    expect(validateEmail(''), isNotNull);
    expect(validateEmail('alice'), isNotNull);
    expect(validateEmail('alice@mail'), isNotNull);
    expect(validateEmail('  alice@mail.com '), isNull);
  });

  test('validateNewPassword checks length and confirmation', () {
    expect(validateNewPassword('', ''), 'Enter a new password.');
    expect(validateNewPassword('short', 'short'), contains('8 characters'));
    expect(validateNewPassword('longenough', 'different'), contains('match'));
    expect(validateNewPassword('longenough', 'longenough'), isNull);
  });

  test('validateOtp accepts exactly 6 digits', () {
    expect(validateOtp(''), isNotNull);
    expect(validateOtp('12345'), isNotNull);
    expect(validateOtp('12a456'), isNotNull);
    expect(validateOtp('1234567'), isNotNull);
    expect(validateOtp(' 123456 '), isNull);
  });

  testWidgets('forgot password shows an error for an invalid email', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: ForgotPasswordScreen(initialEmail: 'nope')),
    );
    await tester.tap(find.text('SEND CODE'));
    await tester.pump();
    expect(find.text('Enter a valid email address.'), findsOneWidget);
  });

  test('theme starts light and toggles the palette', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    final controller = ThemeController.instance;
    expect(controller.value, ThemeMode.light);
    expect(kCream, AppPalette.light.background);

    controller.toggle();
    expect(controller.value, ThemeMode.dark);
    expect(kCream, AppPalette.dark.background);

    controller.setMode(ThemeMode.light);
    expect(kMainText, AppPalette.light.mainText);
  });
}
