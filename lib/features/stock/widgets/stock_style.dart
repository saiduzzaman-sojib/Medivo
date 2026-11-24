import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/expiry.dart';

Color levelColor(MedivoColors c, ExpiryLevel level) => switch (level) {
      ExpiryLevel.expired => c.danger,
      ExpiryLevel.critical => c.danger,
      ExpiryLevel.warning => c.warning,
      ExpiryLevel.ok => c.primary,
    };

/// Wraps a sheet so the keyboard never hides the fields.
Future<T?> showMedivoSheet<T>(BuildContext context, WidgetBuilder builder) {
  final c = context.mc;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: c.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: builder(ctx),
    ),
  );
}

class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 44,
        height: 5,
        decoration: BoxDecoration(
          color: context.mc.muted.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(9),
        ),
      ),
    );
  }
}

class ErrorBanner extends StatelessWidget {
  const ErrorBanner(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.mc;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.danger.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.danger.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: c.danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(color: c.danger, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}