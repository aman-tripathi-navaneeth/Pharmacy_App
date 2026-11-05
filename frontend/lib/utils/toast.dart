import 'package:flutter/material.dart';

import 'app_sounds.dart';

/// Top-right toast notifications shown via the overlay so they float at the
/// top of the screen (SnackBars are pinned to the bottom on desktop).
class AppToast {
  AppToast._();

  static void show(
    BuildContext context,
    String message, {
    bool success = true,
    Duration duration = const Duration(seconds: 3),
  }) {
    final OverlayState? overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ToastMessage(
        message: message,
        success: success,
        onDismiss: () {
          if (entry.mounted) entry.remove();
        },
      ),
    );
    overlay.insert(entry);
    AppSounds.playAlert();
    Future<void>.delayed(duration, () {
      if (entry.mounted) entry.remove();
    });
  }
}

/// One-shot message carried across navigation so the login screen can show
/// a "signed out" confirmation after the previous route was disposed.
class AppFlash {
  AppFlash._();

  static String? pending;

  static void set(String message) => pending = message;

  static String? take() {
    final value = pending;
    pending = null;
    return value;
  }
}

class _ToastMessage extends StatefulWidget {
  const _ToastMessage({
    required this.message,
    required this.success,
    required this.onDismiss,
  });

  final String message;
  final bool success;
  final VoidCallback onDismiss;

  @override
  State<_ToastMessage> createState() => _ToastMessageState();
}

class _ToastMessageState extends State<_ToastMessage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _offset;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _offset = Tween<Offset>(
      begin: const Offset(1.0, -0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = widget.success ? const Color(0xFF059669) : const Color(0xFFDC2626);
    return Positioned(
      top: 12,
      right: 12,
      child: FadeTransition(
        opacity: _controller,
        child: SlideTransition(
          position: _offset,
          child: Material(
            color: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 360),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: accent.withValues(alpha: 0.35)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    widget.success
                        ? Icons.check_circle_rounded
                        : Icons.error_outline_rounded,
                    color: accent,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      widget.message,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: widget.onDismiss,
                    child: Icon(Icons.close, size: 16, color: const Color(0xFF94A3B8)),
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
