import 'package:flutter/material.dart';

import '../../core/models/role.dart';
import '../../shared/widgets/module_page.dart';

class StockPage extends StatelessWidget {
  const StockPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const ModulePage(
      title: 'Stock and batches',
      subtitle: 'Import sales, add batches, validate stock',
      builtInStep: 'Step 5',
      permissions: [Permission.importData, Permission.addBatch, Permission.validateStock],
    );
  }
}