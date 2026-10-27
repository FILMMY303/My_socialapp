import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

class FriendsScreen extends StatelessWidget {
  const FriendsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCream,
      appBar: AppBar(
        backgroundColor: kCream,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: kMainText),
        ),
        title: Text(
          'Friend',
          style: TextStyle(color: kMainText, fontWeight: FontWeight.w700),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Column(
          children: [
            const SizedBox(height: 10),
            _FriendRow(name: 'My Friend Profile Name', active: true),
            const Divider(height: 1, color: Color(0xFFE2E5EC)),
            _FriendRow(name: 'My Friend Profile Name 2', active: false),
          ],
        ),
      ),
    );
  }
}

class _FriendRow extends StatelessWidget {
  const _FriendRow({required this.name, required this.active});

  final String name;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: Color(0xFFE6E9F5),
                child: Text(
                  'M',
                  style: TextStyle(
                    color: kMainText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Positioned(
                right: -1,
                bottom: -1,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: active ? kGreen : const Color(0xFFB7BDC9),
                    border: Border.all(color: kCream, width: 2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Text(
            name,
            style: TextStyle(
              fontSize: 15,
              color: kMainText,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
