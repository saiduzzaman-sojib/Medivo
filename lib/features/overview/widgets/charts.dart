import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/format.dart';
import '../data/overview_calc.dart';
import '../overview_providers.dart';

const _orange = Color(0xFFD9803F);

Color bucketColor(MedivoColors c, Bucket b) => switch (b) {
      Bucket.expired => c.danger,
      Bucket.critical => _orange,
      Bucket.warning => c.warning,
      Bucket.ok => c.primary,
    };

TextStyle _axis(MedivoColors c) => TextStyle(color: c.muted, fontSize: 11);

TextStyle _tip(MedivoColors c) =>
    TextStyle(color: c.ink, fontWeight: FontWeight.w700, fontSize: 12);

/// A round step for the y axis, never below 1.
double _niceStep(double max) {
  final raw = max / 4;
  if (raw <= 0) return 1;
  final pow10 = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  final n = raw / pow10;
  final step = n <= 1 ? 1 : (n <= 2 ? 2 : (n <= 5 ? 5 : 10));
  return math.max(1.0, step * pow10);
}

class LegendDot extends StatelessWidget {
  const LegendDot({super.key, required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: context.mc.muted, fontSize: 12.5)),
      ],
    );
  }
}

class DemandChart extends StatelessWidget {
  const DemandChart({super.key, required this.days, required this.kind});

  final List<DemandDay> days;
  final ChartKind kind;

  @override
  Widget build(BuildContext context) {
    final c = context.mc;
    final values = [
      for (final d in days)
        if (d.quantity != null) d.quantity!.toDouble(),
    ];
    if (values.isEmpty) {
      return SizedBox(
        height: 200,
        child: Center(
          child: Text(
            'No sales recorded for this product and branch yet.',
            textAlign: TextAlign.center,
            style: TextStyle(color: c.muted),
          ),
        ),
      );
    }

    final peak = values.reduce(math.max) * 1.15;
    final step = _niceStep(peak <= 0 ? 4 : peak);
    final maxY = math.max(step, (peak / step).ceil() * step);

    final titles = FlTitlesData(
      topTitles: const AxisTitles(),
      rightTitles: const AxisTitles(),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 40,
          interval: step,
          getTitlesWidget: (v, meta) => Text(v.toInt().toString(), style: _axis(c)),
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 28,
          interval: 1,
          getTitlesWidget: (v, meta) {
            final i = v.toInt();
            if (i < 0 || i >= days.length || i % 7 != 0) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(shortDate(days[i].day), style: _axis(c)),
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
                final d = days[group.x];
                final tag = d.promotion ? '\nPromotion day' : '';
                return BarTooltipItem(
                  '${shortDate(d.day)}\n${rod.toY.toInt()} units$tag',
                  _tip(c),
                );
              },
            ),
          ),
          barGroups: [
            for (var i = 0; i < days.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: (days[i].quantity ?? 0).toDouble(),
                    width: 6,
                    color: days[i].quantity == null
                        ? Colors.transparent
                        : (days[i].promotion ? c.warning : c.secondary),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ],
              ),
          ],
        ),
      );
    } else {
      chart = LineChart(
        LineChartData(
          minX: 0,
          maxX: (days.length - 1).toDouble(),
          minY: 0,
          maxY: maxY,
          gridData: grid,
          borderData: FlBorderData(show: false),
          titlesData: titles,
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => c.raised,
              getTooltipItems: (spots) => [
                for (final s in spots)
                  LineTooltipItem(
                    '${shortDate(days[s.x.toInt()].day)}\n${s.y.toInt()} units',
                    _tip(c),
                  ),
              ],
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (var i = 0; i < days.length; i++)
                  if (days[i].quantity != null)
                    FlSpot(i.toDouble(), days[i].quantity!.toDouble()),
              ],
              isCurved: false,
              color: c.primary,
              barWidth: 3,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: kind == ChartKind.area,
                color: c.primary.withValues(alpha: 0.18),
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(height: 230, child: chart);
  }
}

class HealthChart extends StatelessWidget {
  const HealthChart({super.key, required this.buckets, required this.kind});

  final Buckets buckets;
  final HealthKind kind;

  @override
  Widget build(BuildContext context) {
    final c = context.mc;
    if (buckets.total == 0) {
      return SizedBox(
        height: 160,
        child: Center(child: Text('No stock value yet.', style: TextStyle(color: c.muted))),
      );
    }

    int pct(Bucket b) => (buckets.share(b) * 100).round();

    final legend = Column(
      children: [
        for (final b in Bucket.values)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: bucketColor(c, b),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(b.label)),
                Text('${pct(b)}%', style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(width: 10),
                SizedBox(
                  width: 78,
                  child: Text(formatTaka(buckets.of(b)),
                      textAlign: TextAlign.right,
                      style: TextStyle(color: c.muted, fontSize: 12.5)),
                ),
              ],
            ),
          ),
      ],
    );

    if (kind == HealthKind.bars) {
      return Column(
        children: [
          for (final b in Bucket.values)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(b.label, style: TextStyle(color: c.muted))),
                      Text('${pct(b)}%  ·  ${formatTaka(buckets.of(b))}',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: LinearProgressIndicator(
                      value: buckets.share(b),
                      minHeight: 10,
                      color: bucketColor(c, b),
                      backgroundColor: c.raised,
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    }

    final donut = kind == HealthKind.donut;
    final healthy = ((buckets.share(Bucket.ok) + buckets.share(Bucket.warning)) * 100).round();

    return Column(
      children: [
        SizedBox(
          height: 190,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  startDegreeOffset: -90,
                  sectionsSpace: 2,
                  centerSpaceRadius: donut ? 54 : 0,
                  sections: [
                    for (final b in Bucket.values)
                      if (buckets.of(b) > 0)
                        PieChartSectionData(
                          value: buckets.of(b),
                          color: bucketColor(c, b),
                          radius: donut ? 34 : 84,
                          showTitle: !donut && buckets.share(b) >= 0.08,
                          title: '${pct(b)}%',
                          titleStyle: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                  ],
                ),
              ),
              if (donut)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('$healthy%',
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                    Text('healthy', style: TextStyle(color: c.muted, fontSize: 12)),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        legend,
      ],
    );
  }
}

class BranchExposure extends StatelessWidget {
  const BranchExposure({super.key, required this.data});

  final Map<String, Buckets> data;

  @override
  Widget build(BuildContext context) {
    final c = context.mc;
    final max = data.values.fold<double>(0, (m, b) => math.max(m, b.total));
    if (max == 0) {
      return SizedBox(
        height: 120,
        child: Center(child: Text('No stock value yet.', style: TextStyle(color: c.muted))),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final e in data.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    Text(formatTaka(e.value.total), style: TextStyle(color: c.muted)),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: SizedBox(
                    height: 14,
                    width: double.infinity,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: (e.value.total / max).clamp(0.05, 1.0),
                        child: Row(
                          children: [
                            for (final b in Bucket.values)
                              if (e.value.of(b) > 0)
                                Expanded(
                                  flex: math.max(1, e.value.of(b).round()),
                                  child: ColoredBox(
                                    color: bucketColor(c, b),
                                    child: const SizedBox.expand(),
                                  ),
                                ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [
            for (final b in Bucket.values) LegendDot(color: bucketColor(c, b), label: b.label),
          ],
        ),
      ],
    );
  }
}

class MedicineRiskChart extends StatelessWidget {
  const MedicineRiskChart({super.key, required this.risks});

  final List<MedicineRisk> risks;

  @override
  Widget build(BuildContext context) {
    final c = context.mc;
    if (risks.isEmpty) {
      return SizedBox(
        height: 140,
        child: Center(
          child: Text('Nothing is expired or close to expiry.', style: TextStyle(color: c.muted)),
        ),
      );
    }
    final peak = risks.map((r) => math.max(r.expired, r.soon)).reduce(math.max) * 1.2;
    final step = _niceStep(peak);
    final maxY = math.max(step, (peak / step).ceil() * step);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 230,
          child: BarChart(
            BarChartData(
              minY: 0,
              maxY: maxY,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: step,
                getDrawingHorizontalLine: (_) => FlLine(color: c.line, strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 48,
                    interval: step,
                    getTitlesWidget: (v, meta) => Text(compactTaka(v), style: _axis(c)),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    getTitlesWidget: (v, meta) {
                      final i = v.toInt();
                      if (i < 0 || i >= risks.length) return const SizedBox.shrink();
                      final name = risks[i].medicine.name.split(' ').first;
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          name.length > 7 ? '${name.substring(0, 7)}.' : name,
                          style: _axis(c),
                        ),
                      );
                    },
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => c.raised,
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final r = risks[group.x];
                    final label = rodIndex == 0 ? 'Expired' : 'Expiring in 90 days';
                    return BarTooltipItem(
                      '${r.medicine.name}\n$label: ${formatTaka(rod.toY)}',
                      _tip(c),
                    );
                  },
                ),
              ),
              barGroups: [
                for (var i = 0; i < risks.length; i++)
                  BarChartGroupData(
                    x: i,
                    barsSpace: 4,
                    barRods: [
                      BarChartRodData(
                        toY: risks[i].expired,
                        width: 12,
                        color: c.danger,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                      ),
                      BarChartRodData(
                        toY: risks[i].soon,
                        width: 12,
                        color: c.warning,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 14,
          children: [
            LegendDot(color: c.danger, label: 'Expired'),
            LegendDot(color: c.warning, label: 'Expiring in 90 days'),
          ],
        ),
      ],
    );
  }
}