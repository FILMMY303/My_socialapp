import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/validators.dart';
import '../widgets/auth_widgets.dart';
import '../widgets/common_widgets.dart';

/// Resets a forgotten password with a 6-digit code sent by email.
///
/// Verifying the code signs the user in with a recovery session; [AuthGate]
/// then shows the screen for choosing a new password. No link is involved,
/// so this works the same in a desktop browser, a phone browser or the app.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail = ''});

  final String initialEmail;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  /// Supabase allows one reset email per address every 60 seconds.
  static const _resendDelay = 60;

  late final _emailController = TextEditingController(
    text: widget.initialEmail,
  );
  final _codeController = TextEditingController();
  bool _isBusy = false;
  String? _errorMessage;
  String? _infoMessage;

  /// Address the code was sent to; null while still asking for the email.
  String? _sentTo;
  int _cooldown = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final email = _sentTo ?? _emailController.text.trim();
    final invalid = validateEmail(email);
    if (invalid != null) {
      setState(() => _errorMessage = invalid);
      return;
    }

    final resending = _sentTo != null;
    setState(() {
      _isBusy = true;
      _errorMessage = null;
      _infoMessage = null;
    });
    try {
      await Supabase.instance.client.auth
          .resetPasswordForEmail(email)
          .withNetworkTimeout();
      if (!mounted) return;
      setState(() {
        _sentTo = email;
        _codeController.clear();
        if (resending) _infoMessage = 'A new code has been sent.';
      });
      _startCooldown();
    } on AuthException catch (error) {
      if (mounted) setState(() => _errorMessage = error.message);
    } catch (error) {
      if (mounted) {
        setState(() => _errorMessage = AppException.from(error).message);
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _verifyCode() async {
    final email = _sentTo;
    if (email == null || _isBusy) return;
    final code = _codeController.text.trim();
    final invalid = validateOtp(code);
    if (invalid != null) {
      setState(() => _errorMessage = invalid);
      return;
    }

    setState(() {
      _isBusy = true;
      _errorMessage = null;
      _infoMessage = null;
    });
    try {
      // Emits AuthChangeEvent.passwordRecovery, which makes AuthGate show
      // the new password screen underneath this route.
      await Supabase.instance.client.auth
          .verifyOTP(email: email, token: code, type: OtpType.recovery)
          .withNetworkTimeout();
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on AuthException catch (error) {
      if (!mounted) return;
      final expired =
          error.code == 'otp_expired' ||
          error.message.toLowerCase().contains('expired') ||
          error.message.toLowerCase().contains('invalid');
      setState(() {
        _errorMessage = expired
            ? 'The code is wrong or has expired. Check the latest email or '
                  'send a new code.'
            : error.message;
        _codeController.clear();
      });
    } catch (error) {
      if (mounted) {
        setState(() => _errorMessage = AppException.from(error).message);
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _cooldown = _resendDelay);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _cooldown--);
      if (_cooldown <= 0) timer.cancel();
    });
  }

  void _useAnotherEmail() {
    _timer?.cancel();
    setState(() {
      _sentTo = null;
      _cooldown = 0;
      _errorMessage = null;
      _infoMessage = null;
      _codeController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final sentTo = _sentTo;
    return AuthLayout(
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 26),
      child: sentTo == null ? _buildEmailStep() : _buildCodeStep(sentTo),
    );
  }

  Widget _buildEmailStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AuthCardHeading(
          title: 'Forgot password?',
          subtitle:
              'Enter the email you registered with and we will send you a '
              '6-digit code to reset your password.',
        ),
        const SizedBox(height: 22),
        const AuthFieldLabel('Email'),
        AuthField(
          hintText: 'youmail@example.com',
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          autofocus: widget.initialEmail.isEmpty,
          onSubmitted: _isBusy ? null : (_) => _sendCode(),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 10),
          AuthFeedback(errorMessage: _errorMessage),
        ],
        const SizedBox(height: 22),
        AuthPillButton(
          label: 'SEND CODE',
          fontSize: 20,
          busy: _isBusy,
          onPressed: _isBusy ? null : _sendCode,
        ),
        const SizedBox(height: 18),
        AuthSwitchLink(
          question: 'Remember your password?',
          action: 'Login',
          onTap: _isBusy ? null : () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _buildCodeStep(String email) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AuthCardHeading(
          title: 'Enter the code',
          subtitle:
              'If an account exists for $email, we sent it a 6-digit code. '
              'It expires in 1 hour.',
        ),
        const SizedBox(height: 22),
        _CodeField(
          controller: _codeController,
          enabled: !_isBusy,
          onCompleted: _verifyCode,
        ),
        if (_errorMessage != null || _infoMessage != null) ...[
          const SizedBox(height: 10),
          AuthFeedback(
            errorMessage: _errorMessage,
            successMessage: _infoMessage,
          ),
        ],
        const SizedBox(height: 22),
        AuthPillButton(
          label: 'VERIFY',
          fontSize: 20,
          busy: _isBusy,
          onPressed: _isBusy ? null : _verifyCode,
        ),
        const SizedBox(height: 10),
        Center(
          child: TextButton(
            onPressed: _isBusy || _cooldown > 0 ? null : _sendCode,
            child: Text(
              _cooldown > 0 ? 'Resend code in ${_cooldown}s' : 'Resend code',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        AuthSwitchLink(
          question: 'Wrong address?',
          action: 'Use another email',
          onTap: _isBusy ? null : _useAnotherEmail,
        ),
      ],
    );
  }
}

/// Large, spaced-out field for a 6-digit code. Calls [onCompleted] as soon as
/// the last digit is typed (or a full code is pasted).
class _CodeField extends StatelessWidget {
  const _CodeField({
    required this.controller,
    required this.enabled,
    required this.onCompleted,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onCompleted;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(22),
      borderSide: BorderSide.none,
    );
    return TextField(
      controller: controller,
      enabled: enabled,
      autofocus: true,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      autofillHints: const [AutofillHints.oneTimeCode],
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(otpLength),
      ],
      onChanged: (value) {
        if (value.length == otpLength) onCompleted();
      },
      onSubmitted: (_) => onCompleted(),
      style: TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.w700,
        letterSpacing: 12,
        color: kMainText,
      ),
      decoration: InputDecoration(
        filled: true,
        fillColor: kInputBg,
        hintText: '000000',
        hintStyle: TextStyle(color: kMuted, letterSpacing: 12),
        border: border,
        enabledBorder: border,
        disabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: const BorderSide(color: kGreen, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
      ),
    );
  }
}
