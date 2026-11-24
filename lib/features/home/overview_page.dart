import 'package:flutter/material.dart';

import '../../core/models/role.dart';
import '../../shared/widgets/module_page.dart';

class OverviewPage extends StatelessWidget {
  const OverviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const ModulePage(
      title: 'Overview',
      subtitle: 'KPIs, demand chart, stock health and branch exposure',
      builtInStep: 'Step 6',
      permissions: [Permission.viewOverview, Permission.viewAudit],
    );
  }
}