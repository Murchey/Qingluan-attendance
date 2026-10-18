import 'dart:async';

import 'package:flutter/cupertino.dart';
import '../theme/design_tokens.dart';

OverlayEntry? _current;
Timer? _timer;

/// Non-blocking transient message shown above the bottom navigation.
///
/// The app deliberately avoids a toast plugin: this overlay keeps the same
/// rounded, dark control language as the rest of the Cupertino UI and works in
/// widget tests without platform channels.
void showToast(
  BuildContext context,
  String message, {
  IconData icon = CupertinoIcons.exclamationmark_circle,
  Duration duration = const Duration(seconds: 3),
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _timer?.cancel();
  final previous = _current;
  if (previous != null && previous.mounted) previous.remove();
  _current = null;

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => _Toast(message: message, icon: icon),
  );
  _current = entry;
  overlay.insert(entry);
  _timer = Timer(duration, () {
    if (entry.mounted) entry.remove();
    if (identical(_current, entry)) _current = null;
  });
}

class _Toast extends StatelessWidget {
  const _Toast({required this.message, required this.icon});
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Positioned(
      left: Gap.lg,
      right: Gap.lg,
      bottom: bottom + 96,
      child: IgnorePointer(
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) => Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, (1 - value) * 10),
                child: child,
              ),
            ),
            child: Container(
              key: const ValueKey('app-toast'),
              constraints: const BoxConstraints(maxWidth: 430),
              padding: const EdgeInsets.symmetric(
                horizontal: Gap.md,
                vertical: Gap.sm,
              ),
              decoration: BoxDecoration(
                color: const Color(0xF01B1D23),
                borderRadius: BorderRadius.circular(Radii.control),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0x33000000),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18, color: const Color(0xFFFFD8A8)),
                  const SizedBox(width: Gap.xs),
                  Flexible(
                    child: Text(
                      message,
                      style: const TextStyle(
                        color: CupertinoColors.white,
                        fontSize: 14,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
