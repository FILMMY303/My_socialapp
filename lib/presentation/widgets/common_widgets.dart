import 'package:flutter/material.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/app_colors.dart';

class AuthFeedback extends StatelessWidget {
  const AuthFeedback({super.key, this.errorMessage, this.successMessage});

  final String? errorMessage;
  final String? successMessage;

  @override
  Widget build(BuildContext context) {
    final message = errorMessage ?? successMessage;
    if (message == null) return const SizedBox.shrink();

    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        message,
        style: TextStyle(
          color: errorMessage == null ? kGreen : kRed,
          fontSize: 12,
        ),
      ),
    );
  }
}

class BrandHeader extends StatelessWidget {
  const BrandHeader({super.key, this.centered = false});

  final bool centered;

  @override
  Widget build(BuildContext context) {
    final children = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: kGreen,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Center(
            child: Text(
              's',
              style: TextStyle(
                color: kWhite,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        // Shrinks instead of overflowing when header buttons share the row.
        Flexible(
          child: Text(
            'social network',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: kMainText,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );

    return centered ? Center(child: children) : children;
  }
}

class GreenActionButton extends StatelessWidget {
  const GreenActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.height = 52,
  });

  final String label;
  final VoidCallback? onPressed;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: kGreen,
          foregroundColor: kWhite,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          elevation: 0,
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

class FormLabel extends StatelessWidget {
  const FormLabel({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: kMainText,
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class CustomInputField extends StatelessWidget {
  const CustomInputField({
    super.key,
    this.hintText,
    this.icon,
    this.obscureText = false,
    this.controller,
    this.keyboardType,
  });

  final String? hintText;
  final IconData? icon;
  final bool obscureText;
  final TextEditingController? controller;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType:
          keyboardType ??
          (obscureText ? TextInputType.visiblePassword : TextInputType.text),
      decoration: InputDecoration(
        filled: true,
        fillColor: kInputBg,
        hintText: hintText,
        hintStyle: TextStyle(color: kMuted, fontSize: 14),
        prefixIcon: icon != null ? Icon(icon, color: kMuted, size: 20) : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: kGreen, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
      ),
    );
  }
}

class PlaceholderMedia extends StatelessWidget {
  const PlaceholderMedia({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 20,
  });

  final double width;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFD9DDE6),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: CustomPaint(
        painter: DashedPlaceholderPainter(),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class DashedPlaceholderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFA5ACB7)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    const dashWidth = 6.0;
    const dashGap = 4.0;
    final path = Path();

    for (double x = 0; x < size.width + size.height; x += dashWidth + dashGap) {
      path.moveTo(x, 0);
      path.lineTo(x - size.height, size.height);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Centered error message with a "Try again" button.
class ErrorRetry extends StatelessWidget {
  const ErrorRetry({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: kRed, size: 32),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: kMainText),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

/// A user-friendly message for any error.
String errorMessage(Object error) => AppException.from(error).message;

/// Shows [error] as a snackbar with a user-friendly message.
void showErrorSnackBar(BuildContext context, Object error) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(AppException.from(error).message),
        backgroundColor: kRed,
      ),
    );
}

/// Asks the user to confirm a destructive action.
Future<bool> confirmDelete(BuildContext context, String what) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Delete $what?'),
      content: Text('This $what will be removed for everyone.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: TextButton.styleFrom(foregroundColor: kRed),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Opens a dialog to edit [initialText]. Returns the new text, or null when
/// cancelled. [onSave] may throw; its error is shown inside the dialog.
Future<String?> showEditTextDialog(
  BuildContext context, {
  required String title,
  required String initialText,
  required int maxLength,
  required Future<void> Function(String text) onSave,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _EditTextDialog(
      title: title,
      initialText: initialText,
      maxLength: maxLength,
      onSave: onSave,
    ),
  );
}

class _EditTextDialog extends StatefulWidget {
  const _EditTextDialog({
    required this.title,
    required this.initialText,
    required this.maxLength,
    required this.onSave,
  });

  final String title;
  final String initialText;
  final int maxLength;
  final Future<void> Function(String text) onSave;

  @override
  State<_EditTextDialog> createState() => _EditTextDialogState();
}

class _EditTextDialogState extends State<_EditTextDialog> {
  late final _controller = TextEditingController(text: widget.initialText);
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(_controller.text);
      if (mounted) Navigator.of(context).pop(_controller.text);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = AppException.from(error).message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 400,
        child: TextField(
          controller: _controller,
          autofocus: true,
          minLines: 2,
          maxLines: 8,
          maxLength: widget.maxLength,
          enabled: !_saving,
          decoration: InputDecoration(
            errorText: _error,
            border: const OutlineInputBorder(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _saving ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
