import 'package:flutter/material.dart';

import '../../core/models/role.dart';
import '../../shared/widgets/module_page.dart';

class ForecastPage extends StatelessWidget {
  const ForecastPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const ModulePage(
      title: 'Demand estimates',
      subtitle: 'Forecast, metrics, manual forecast and jobs',
      builtInStep: 'Step 7',
      permissions: [Permission.runForecast, Permission.manualForecast, Permission.viewOverview],
    );
  }
}