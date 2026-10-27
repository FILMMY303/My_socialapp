final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// Error message for [email], or null when it looks valid.
String? validateEmail(String email) {
  final value = email.trim();
  if (value.isEmpty) return 'Enter your email address.';
  if (!_email.hasMatch(value)) return 'Enter a valid email address.';
  return null;
}

/// Error message for a new password and its confirmation, or null when valid.
String? validateNewPassword(String password, String confirmation) {
  if (password.isEmpty) return 'Enter a new password.';
  if (password.length < 8) return 'Password must be at least 8 characters.';
  if (password != confirmation) return 'Passwords do not match.';
  return null;
}

/// Digits in the password reset code (Supabase "Email OTP Length").
const otpLength = 6;

final _otp = RegExp(
  r'^\d{'
  '$otpLength'
  r'}$',
);

/// Error message for a password reset code, or null when it looks valid.
String? validateOtp(String code) {
  if (code.trim().isEmpty) return 'Enter the code from the email.';
  if (!_otp.hasMatch(code.trim())) return 'The code has $otpLength digits.';
  return null;
}
