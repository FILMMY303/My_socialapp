import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/validators.dart';
import '../widgets/auth_widgets.dart';
import '../widgets/common_widgets.dart';

/// Shown after the user opens a password reset link: sets a new password for
/// the recovery session, then continues into the app via [onDone].
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isBusy = false;
  String? _errorMessage;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final password = _passwordController.text;
    final invalid = validateNewPassword(password, _confirmController.text);
    if (invalid != null) {
      setState(() => _errorMessage = invalid);
      return;
    }

    setState(() {
      _isBusy = true;
      _errorMessage = null;
    });
    try {
      await Supabase.instance.client.auth
          .updateUser(UserAttributes(password: password))
          .withNetworkTimeout();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your password has been changed.')),
      );
      widget.onDone();
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

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AuthCardHeading(
            title: 'Set a new password',
            subtitle: 'Choose a new password for your account.',
          ),
          const SizedBox(height: 22),
          const AuthFieldLabel('New Password'),
          AuthField(
            hintText: 'At least 8 characters long',
            obscureText: true,
            autofocus: true,
            controller: _passwordController,
          ),
          const SizedBox(height: 14),
          const AuthFieldLabel('Confirm Password'),
          AuthField(
            hintText: 'Confirm your new password',
            obscureText: true,
            controller: _confirmController,
            onSubmitted: _isBusy ? null : (_) => _save(),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 10),
            AuthFeedback(errorMessage: _errorMessage),
          ],
          const SizedBox(height: 22),
          AuthPillButton(
            label: 'SAVE PASSWORD',
            fontSize: 18,
            busy: _isBusy,
            onPressed: _isBusy ? null : _save,
          ),
          const SizedBox(height: 18),
          AuthSwitchLink(
            question: 'Changed your mind?',
            action: 'Cancel',
            // The recovery link already signed the user in; cancelling
            // signs out so the old password keeps working as before.
            onTap: _isBusy
                ? null
                : () => Supabase.instance.client.auth.signOut(),
          ),
        ],
      ),
    );
  }
}
