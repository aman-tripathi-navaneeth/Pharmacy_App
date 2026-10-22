import 'package:flutter/material.dart';

/// Wraps the content in a centered mobile viewport when running on Web or Desktop,
/// and renders full-screen on native mobile devices.
class MobileViewWrapper extends StatelessWidget {
  final Widget child;

  const MobileViewWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // If screen width is wider than a phone (e.g., Web/Desktop), display in mobile frame
        if (constraints.maxWidth > 500) {
          return Scaffold(
            backgroundColor: const Color(0xFFE2E8F0),
            body: Center(
              child: Container(
                width: 440,
                height: constraints.maxHeight > 920 ? 880 : constraints.maxHeight * 0.96,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.14),
                      blurRadius: 28,
                      offset: const Offset(0, 10),
                    ),
                  ],
                  border: Border.all(
                    color: const Color(0xFFCBD5E1),
                    width: 1.5,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: child,
              ),
            ),
          );
        }

        // Native mobile view: fill device screen
        return child;
      },
    );
  }
}
