import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/validators.dart';
import '../widgets/auth_widgets.dart';
import '../widgets/common_widgets.dart';
import 'forgot_password_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isLogin = true;
  bool _isBusy = false;
  String? _errorMessage;
  String? _successMessage;
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _toggleForm() {
    setState(() {
      _isLogin = !_isLogin;
      _errorMessage = null;
      _successMessage = null;
    });
  }

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Enter your email and password.');
      return;
    }

    setState(() {
      _isBusy = true;
      _errorMessage = null;
      _successMessage = null;
    });
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );
    } on AuthException catch (error) {
      if (mounted) setState(() => _errorMessage = error.message);
    } catch (error) {
      if (mounted) setState(() => _errorMessage = 'Login failed: $error');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _register() async {
    final username = _usernameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || email.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Complete all required fields.');
      return;
    }
    final invalid =
        validateEmail(email) ??
        validateNewPassword(password, _confirmPasswordController.text);
    if (invalid != null) {
      setState(() => _errorMessage = invalid);
      return;
    }

    setState(() {
      _isBusy = true;
      _errorMessage = null;
      _successMessage = null;
    });
    try {
      final response = await Supabase.instance.client.auth.signUp(
        email: email,
        password: password,
        data: {'username': username},
      );
      if (mounted && response.session == null) {
        setState(() {
          _isLogin = true;
          _successMessage =
              'Account created, but email confirmation is enabled for this '
              'project. Disable “Confirm email” in Supabase Auth settings to '
              'let users sign in immediately after registering.';
        });
      }
    } on AuthException catch (error) {
      if (mounted) {
        setState(() => _errorMessage = error.message);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _errorMessage = 'Registration failed: $error');
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  void _openForgotPassword() {
    setState(() {
      _errorMessage = null;
      _successMessage = null;
    });
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ForgotPasswordScreen(initialEmail: _emailController.text.trim()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      padding: EdgeInsets.fromLTRB(
        20,
        _isLogin ? 28 : 26,
        20,
        _isLogin ? 34 : 26,
      ),
      child: _isLogin
          ? _LoginForm(
              onToggle: _toggleForm,
              onSubmit: _login,
              onForgotPassword: _openForgotPassword,
              emailController: _emailController,
              passwordController: _passwordController,
              isBusy: _isBusy,
              errorMessage: _errorMessage,
              successMessage: _successMessage,
            )
          : _RegisterForm(
              onToggle: _toggleForm,
              onSubmit: _register,
              usernameController: _usernameController,
              emailController: _emailController,
              passwordController: _passwordController,
              confirmPasswordController: _confirmPasswordController,
              isBusy: _isBusy,
              errorMessage: _errorMessage,
            ),
    );
  }
}

class _LoginForm extends StatelessWidget {
  const _LoginForm({
    required this.onToggle,
    required this.onSubmit,
    required this.onForgotPassword,
    required this.emailController,
    required this.passwordController,
    required this.isBusy,
    this.errorMessage,
    this.successMessage,
  });

  final VoidCallback onToggle;
  final Future<void> Function() onSubmit;
  final VoidCallback onForgotPassword;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool isBusy;
  final String? errorMessage;
  final String? successMessage;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AuthField(
          hintText: 'Email',
          controller: emailController,
          keyboardType: TextInputType.emailAddress,
          onSubmitted: isBusy ? null : (_) => onSubmit(),
        ),
        const SizedBox(height: 16),
        AuthField(
          hintText: 'Password',
          obscureText: true,
          controller: passwordController,
          onSubmitted: isBusy ? null : (_) => onSubmit(),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: isBusy ? null : onForgotPassword,
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            child: const Text(
              'forgot password?',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: kGreen,
              ),
            ),
          ),
        ),
        if (errorMessage != null || successMessage != null) ...[
          const SizedBox(height: 8),
          AuthFeedback(
            errorMessage: errorMessage,
            successMessage: successMessage,
          ),
        ],
        const SizedBox(height: 4),
        AuthPillButton(
          label: 'LOG IN',
          busy: isBusy,
          onPressed: isBusy ? null : () => onSubmit(),
        ),
        const SizedBox(height: 18),
        AuthSwitchLink(
          question: 'Don’t Have account?',
          action: 'register',
          onTap: isBusy ? null : onToggle,
        ),
      ],
    );
  }
}

class _RegisterForm extends StatelessWidget {
  const _RegisterForm({
    required this.onToggle,
    required this.onSubmit,
    required this.usernameController,
    required this.emailController,
    required this.passwordController,
    required this.confirmPasswordController,
    required this.isBusy,
    this.errorMessage,
  });

  final VoidCallback onToggle;
  final Future<void> Function() onSubmit;
  final TextEditingController usernameController;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final TextEditingController confirmPasswordController;
  final bool isBusy;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AuthFieldLabel('Username'),
        AuthField(hintText: 'username', controller: usernameController),
        const SizedBox(height: 14),
        const AuthFieldLabel('Email'),
        AuthField(
          hintText: 'youmail@example.com',
          controller: emailController,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 14),
        const AuthFieldLabel('Password'),
        AuthField(
          hintText: 'At least 8 characters long',
          obscureText: true,
          controller: passwordController,
        ),
        const SizedBox(height: 14),
        const AuthFieldLabel('Confirm Password'),
        AuthField(
          hintText: 'Confirm your password',
          obscureText: true,
          controller: confirmPasswordController,
          onSubmitted: isBusy ? null : (_) => onSubmit(),
        ),
        if (errorMessage != null) ...[
          const SizedBox(height: 10),
          AuthFeedback(errorMessage: errorMessage),
        ],
        const SizedBox(height: 18),
        AuthSwitchLink(
          question: 'Already have account?',
          action: 'Login',
          onTap: isBusy ? null : onToggle,
        ),
        const SizedBox(height: 10),
        AuthPillButton(
          label: 'REGISTER',
          busy: isBusy,
          onPressed: isBusy ? null : () => onSubmit(),
        ),
      ],
    );
  }
}
