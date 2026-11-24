import 'package:flutter/material.dart';

import '../../core/models/role.dart';
import '../../shared/widgets/module_page.dart';

class SecurityPage extends StatelessWidget {
  const SecurityPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const ModulePage(
      title: 'Security and audit',
      subtitle: 'Controls, acceptance checks, backup and audit log',
      builtInStep: 'Step 9',
      permissions: [Permission.viewAudit],
    );
  }
}