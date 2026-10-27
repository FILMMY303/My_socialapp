// Draws the app icon (white "s" on brand green, like the login logo) into
// every Android, iOS and web icon file.
//
//   flutter test tool/generate_app_icons.dart
//
// Runs as a test so it can paint with dart:ui; it writes files, it checks
// nothing. Needs Arial Bold (Windows) for the letter.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _green = Color(0xFF059669);
const _font = 'IconFont';

/// Letter height relative to the visible icon, matching the login logo
/// (18 px text in a 28 px box).
const _letterScale = 0.64;

void main() {
  testWidgets('generate app icons', (tester) async {
    await tester.runAsync(() async {
      final bytes = File(r'C:\Windows\Fonts\arialbd.ttf').readAsBytesSync();
      await (FontLoader(
        _font,
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();

      // Full-bleed square: legacy Android, iOS (no transparency allowed), web.
      final android = {
        'mdpi': 48,
        'hdpi': 72,
        'xhdpi': 96,
        'xxhdpi': 144,
        'xxxhdpi': 192,
      };
      for (final MapEntry(key: density, value: size) in android.entries) {
        await _write(
          'android/app/src/main/res/mipmap-$density/ic_launcher.png',
          await _icon(size),
        );
        // Adaptive foreground: 108 dp canvas, launcher shows the middle 72 dp.
        await _write(
          'android/app/src/main/res/mipmap-$density/ic_launcher_foreground.png',
          await _icon(
            size * 108 ~/ 48,
            background: false,
            visible: size * 72 / 48,
          ),
        );
      }

      final ios = Directory('ios/Runner/Assets.xcassets/AppIcon.appiconset');
      final name = RegExp(r'Icon-App-([\d.]+)x[\d.]+@(\d)x\.png$');
      for (final file in ios.listSync().whereType<File>()) {
        final match = name.firstMatch(file.path);
        if (match == null) continue;
        final size =
            (double.parse(match.group(1)!) * int.parse(match.group(2)!))
                .round();
        await _write(file.path, await _icon(size));
      }

      for (final size in [192, 512]) {
        await _write('web/icons/Icon-$size.png', await _icon(size));
        // Maskable icons may be cropped to a circle: keep the letter in the
        // middle 80 %.
        await _write(
          'web/icons/Icon-maskable-$size.png',
          await _icon(size, visible: size * 0.8),
        );
      }
      await _write('web/favicon.png', await _icon(32));
    });
  });
}

Future<void> _write(String path, Uint8List png) async {
  await File(path).writeAsBytes(png);
  // ignore: avoid_print
  print('wrote $path');
}

/// A [size] px icon. [visible] is the part of the canvas the user sees
/// (smaller for adaptive / maskable icons); the letter is scaled to it.
Future<Uint8List> _icon(
  int size, {
  bool background = true,
  double? visible,
}) async {
  final letterHeight = (visible ?? size.toDouble()) * _letterScale;
  final painter = TextPainter(
    text: TextSpan(
      text: 's',
      style: TextStyle(
        fontFamily: _font,
        fontSize: letterHeight * 1.9, // x-height of Arial is ~0.52 em
        color: Colors.white,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  // Lower-case letters sit low in their line box, so measure the drawn
  // pixels and center those instead.
  final probe = await _render(size, painter, Offset.zero, background: false);
  final bounds = await _inkBounds(probe, size);
  final offset = Offset(
    (size - bounds.width) / 2 - bounds.left,
    (size - bounds.height) / 2 - bounds.top,
  );
  final image = await _render(size, painter, offset, background: background);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

Future<ui.Image> _render(
  int size,
  TextPainter painter,
  Offset offset, {
  required bool background,
}) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  if (background) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
      Paint()..color = _green,
    );
  }
  painter.paint(canvas, offset);
  return recorder.endRecording().toImage(size, size);
}

/// Bounding box of non-transparent pixels in [image].
Future<Rect> _inkBounds(ui.Image image, int size) async {
  final data = (await image.toByteData())!;
  var left = size, top = size, right = 0, bottom = 0;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      if (data.getUint8((y * size + x) * 4 + 3) > 32) {
        if (x < left) left = x;
        if (x > right) right = x;
        if (y < top) top = y;
        if (y > bottom) bottom = y;
      }
    }
  }
  return Rect.fromLTRB(
    left.toDouble(),
    top.toDouble(),
    right + 1.0,
    bottom + 1.0,
  );
}
