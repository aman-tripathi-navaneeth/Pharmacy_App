/// Shared frame for the three dashboard tabs (Member 11).
///
/// Design tokens from the prototype (docs/design/): ink #222222, secondary
/// #555555, muted #8A8A8A, hairline #D9D9D9, chip background #F3F3F3, paper #FAFAFA.
/// Every tab renders [DashboardHeader] so the store row and tab bar stay identical
/// across frames 01-11.
library;

import 'package:flutter/material.dart';

/// The three top-level tabs from the prototype frames.
enum DashboardTab { today, summary, purchases }

const Color ink = Color(0xFF222222);
const Color secondary = Color(0xFF555555);
const Color muted = Color(0xFF8A8A8A);
const Color hairline = Color(0xFFD9D9D9);
const Color chipBg = Color(0xFFF3F3F3);
const Color paper = Color(0xFFFAFAFA);

const String fontFamily = 'Inter';

/// Store row + tab bar. The active tab gets the black underline (frames 08-11).
class DashboardHeader extends StatelessWidget {
  const DashboardHeader({
    super.key,
    required this.storeId,
    required this.statusPill,
    required this.active,
    required this.onTab,
  });

  final String storeId;
  final String statusPill;
  final DashboardTab active;
  final ValueChanged<DashboardTab> onTab;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    storeId,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                  const Text(
                    'మెడికల్ స్టోర్',
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: hairline),
              ),
              child: Text(
                statusPill,
                style: const TextStyle(fontSize: 11, color: secondary),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 40,
          child: Row(
            children: <Widget>[
              for (final DashboardTab tab in DashboardTab.values) ...<Widget>[
                Expanded(
                  child: InkWell(
                    onTap: () => onTab(tab),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Text(
                          switch (tab) {
                            DashboardTab.today => 'Today',
                            DashboardTab.summary => 'Summary',
                            DashboardTab.purchases => 'Purchases',
                          },
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: tab == active
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: tab == active ? ink : muted,
                          ),
                        ),
                        Container(
                          height: 3,
                          color: tab == active ? ink : Colors.transparent,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        Divider(height: 1, thickness: 1, color: hairline),
      ],
    );
  }
}

/// Formats a time as a compact 12-hour label, e.g. "6:40 PM".
String formatTime(DateTime t) {
  final DateTime local = t.toLocal();
  final int hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final String mm = local.minute.toString().padLeft(2, '0');
  return '$hour12:$mm ${local.hour >= 12 ? 'PM' : 'AM'}';
}

/// Formats a date like the prototype: "Mon 12 Oct".
String formatDay(DateTime d) {
  const List<String> weekdays = <String>[
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
  ];
  const List<String> months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${weekdays[d.weekday - 1]} ${d.day} ${months[d.month - 1]}';
}

/// The frame-05 error card, reused by every tab.
class ErrorCard extends StatelessWidget {
  const ErrorCard({super.key, required this.title, required this.message, this.onRetry});

  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: muted),
      ),
      child: Column(
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: muted),
          ),
          if (onRetry != null) ...<Widget>[
            const SizedBox(height: 16),
            SizedBox(
              height: 34,
              child: FilledButton(
                onPressed: onRetry,
                style: FilledButton.styleFrom(
                  backgroundColor: ink,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: const Text('Try again'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
