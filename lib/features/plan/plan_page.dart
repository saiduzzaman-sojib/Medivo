import 'package:flutter/material.dart';

import '../../core/models/role.dart';
import '../../shared/widgets/module_page.dart';

class PlanPage extends StatelessWidget {
  const PlanPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const ModulePage(
      title: 'Expiry-aware plan',
      subtitle: 'Orders, transfers, recalls and outcomes',
      builtInStep: 'Step 8',
      permissions: [
        Permission.reviewPlan,
        Permission.approvePlan,
        Permission.approveTransfer,
        Permission.approveRecall,
        Permission.recordOutcome,
      ],
    );
  }
}