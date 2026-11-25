import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/chart_math.dart';
import '../../../core/utils/format.dart';
import '../../overview/overview_providers.dart';
import '../../overview/widgets/charts.dart';
import '../data/forecast_models.dart';

/// The last 28 recorded days followed by the forecast, with the baseline dashed
/// and (for the AI model) a shaded 80% interval.
class ForecastChart extends StatelessWidget {
  const ForecastChart({super.key, required this.result, required this.kind});

  final ForecastResult result;
  final ChartKind kind;

  static const int shown = 28;

  @override
  Widget build(BuildContext context) {
    final c = context.mc;
    final all = result.history;
    final hist = all.length > shown ? all.sublist(all.length - shown) : all;
    final h = hist.length;
    final pts = result.points;
    final total = h + pts.length;
    DateTime dayAt(int i) => i < h ? hist[i].day : pts[i - h].day;

    final values = <double>[
      for (final d in hist)
        if (d.quantity != null) d.quantity!.toDouble(),
      for (final p in pts) ...[p.value, p.baseline, if (p.high != null) p.high!],
    ];
    final peak = values.isEmpty ? 4.0 : values.reduce(math.max) * 1.15;
    final step = niceStep(peak);
    final maxY = math.max(step, (peak / step).ceil() * step);
    final axis = TextStyle(color: c.muted, fontSize: 11);
    final tip = TextStyle(color: c.ink, fontWeight: FontWeight.w700, fontSize: 12);

    final titles = FlTitlesData(
      topTitles: const AxisTitles(),
      rightTitles: const AxisTitles(),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 40,
          interval: step,
          getTitlesWidget: (v, meta) => Text(v.toInt().toString(), style: axis),
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 28,
          interval: 1,
          getTitlesWidget: (v, meta) {
            final i = v.toInt();
            if (i < 0 || i >= total || i % 7 != 0) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(shortDate(dayAt(i)), style: axis),
            );
          },
        ),
      ),
    );

    final grid = FlGridData(
      show: true,
      drawVerticalLine: false,
      horizontalInterval: step,
      getDrawingHorizontalLine: (_) => FlLine(color: c.line, strokeWidth: 1),
    );

    Widget chart;
    if (kind == ChartKind.bar) {
      chart = BarChart(
        BarChartData(
          minY: 0,
          maxY: maxY,
          gridData: grid,
          borderData: FlBorderData(show: false),
          titlesData: titles,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => c.raised,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final i = group.x;
                final label = i < h ? 'Recorded' : 'Forecast';
                return BarTooltipItem(
                  '${shortDate(dayAt(i))}\n$label: ${rod.toY.toStringAsFixed(1)} units',
                  tip,
                );
              },
            ),
          ),
          barGroups: [
            for (var i = 0; i < total; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: i < h ? (hist[i].quantity ?? 0).toDouble() : pts[i - h].value,
                    width: total > 35 ? 5 : 7,
                    color: i < h
                        ? (hist[i].quantity == null ? Colors.transparent : c.secondary)
                        : c.primary,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ],
              ),
          ],
        ),
      );
    } else {
      final bars = <LineChartBarData>[
        LineChartBarData(
          spots: [
            for (var i = 0; i < h; i++)
              if (hist[i].quantity != null) FlSpot(i.toDouble(), hist[i].quantity!.toDouble()),
          ],
          color: c.secondary,
          barWidth: 3,
          dotData: const FlDotData(show: false),
        ),
        LineChartBarData(
          spots: [for (var k = 0; k < pts.length; k++) FlSpot((h + k).toDouble(), pts[k].value)],
          color: c.primary,
          barWidth: 3,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: kind == ChartKind.area,
            color: c.primary.withValues(alpha: 0.18),
          ),
        ),
      ];
      var baselineIdx = -1;
      if (result.source != ForecastSource.baseline) {
        baselineIdx = bars.length;
        bars.add(LineChartBarData(
          spots: [for (var k = 0; k < pts.length; k++) FlSpot((h + k).toDouble(), pts[k].baseline)],
          color: c.muted,
          barWidth: 2,
          dashArray: const [6, 5],
          dotData: const FlDotData(show: false),
        ));
      }
      var loIdx = -1;
      var hiIdx = -1;
      if (result.hasInterval) {
        loIdx = bars.length;
        bars.add(LineChartBarData(
          spots: [for (var k = 0; k < pts.length; k++) FlSpot((h + k).toDouble(), pts[k].low ?? pts[k].value)],
          color: Colors.transparent,
          barWidth: 0.1,
          dotData: const FlDotData(show: false),
        ));
        hiIdx = bars.length;
        bars.add(LineChartBarData(
          spots: [for (var k = 0; k < pts.length; k++) FlSpot((h + k).toDouble(), pts[k].high ?? pts[k].value)],
          color: Colors.transparent,
          barWidth: 0.1,
          dotData: const FlDotData(show: false),
        ));
      }

      String nameOf(int barIndex) {
        if (barIndex == 0) return 'Recorded';
        if (barIndex == 1) return result.source == ForecastSource.baseline ? 'Baseline' : 'Forecast';
        if (barIndex == baselineIdx) return 'Baseline';
        return '';
      }

      chart = LineChart(
        LineChartData(
          minX: 0,
          maxX: (total - 1).toDouble(),
          minY: 0,
          maxY: maxY,
          gridData: grid,
          borderData: FlBorderData(show: false),
          titlesData: titles,
          betweenBarsData: result.hasInterval
              ? [
                  BetweenBarsData(
                    fromIndex: loIdx,
                    toIndex: hiIdx,
                    color: c.primary.withValues(alpha: 0.16),
                  ),
                ]
              : const [],
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => c.raised,
              getTooltipItems: (spots) => <LineTooltipItem?>[
                for (final s in spots)
                  nameOf(s.barIndex).isEmpty
                      ? null
                      : LineTooltipItem(
                          '${shortDate(dayAt(s.x.toInt()))}\n${nameOf(s.barIndex)}: ${s.y.toStringAsFixed(1)}',
                          tip,
                        ),
              ],
            ),
          ),
          lineBarsData: bars,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 250, child: chart),
        const SizedBox(height: 10),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [
            LegendDot(color: c.secondary, label: 'Recorded sales'),
            LegendDot(
              color: c.primary,
              label: result.source == ForecastSource.baseline ? 'Baseline forecast' : '${result.source.label} forecast',
            ),
            if (result.source != ForecastSource.baseline && kind != ChartKind.bar)
              LegendDot(color: c.muted, label: 'Baseline (dashed)'),
            if (result.hasInterval && kind != ChartKind.bar)
              LegendDot(color: c.primary.withValues(alpha: 0.4), label: '80% range'),
          ],
        ),
      ],
    );
  }
}