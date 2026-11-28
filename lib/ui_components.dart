import 'dart:math';
import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'app_notice.dart';

Future<void> runAction(
  BuildContext context,
  Future<void> Function() action, {
  String? success,
}) async {
  try {
    await action();
    if (context.mounted && success != null) {
      showAppNotice(
        context,
        AppNotice(title: success, tone: NoticeTone.success),
      );
    }
  } catch (e) {
    if (context.mounted) {
      showAppNotice(
        context,
        AppNotice(
          title: '操作未完成',
          message: e.toString(),
          tone: NoticeTone.error,
        ),
      );
    }
  }
}

class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: color ?? context.surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: context.stroke),
    ),
    child: child,
  );
}

class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.color, this.dot = false});
  final String text;
  final Color? color;
  final bool dot;
  @override
  Widget build(BuildContext context) {
    final color = this.color ?? context.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Icon(Icons.circle, size: 6, color: color),
            const SizedBox(width: 5),
          ],
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.trailing, this.subtitle});
  final String title;
  final String? subtitle;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.4,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 5),
                Text(
                  subtitle!,
                  style: TextStyle(fontSize: 11, color: context.muted),
                ),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState(
    this.title,
    this.message, {
    super.key,
    this.icon = Icons.search_off_rounded,
  });
  final String title, message;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(30),
    child: Column(
      children: [
        Icon(icon, color: context.muted, size: 38),
        const SizedBox(height: 14),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text(
          message,
          style: TextStyle(color: context.muted, fontSize: 12),
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}

class SparkChart extends StatelessWidget {
  const SparkChart({
    super.key,
    required this.values,
    this.secondary,
    this.large = false,
    this.color,
  });
  final List<double> values;
  final List<double>? secondary;
  final bool large;
  final Color? color;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: large ? 160 : 32,
    width: double.infinity,
    child: CustomPaint(
      painter: _ChartPainter(
        values,
        secondary,
        color ?? context.accent,
        context.stroke,
        large,
      ),
    ),
  );
}

class _ChartPainter extends CustomPainter {
  _ChartPainter(
    this.values,
    this.secondary,
    this.color,
    this.gridColor,
    this.grid,
  );
  final List<double> values;
  final List<double>? secondary;
  final Color color, gridColor;
  final bool grid;
  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final peak = max(1.0, [...values, ...?secondary].reduce(max)) * 1.2;
    if (grid) {
      for (var i = 0; i < 5; i++) {
        final y = i * size.height / 4;
        canvas.drawLine(
          Offset(0, y),
          Offset(size.width, y),
          Paint()
            ..color = gridColor
            ..strokeWidth = 1,
        );
      }
    }
    void draw(List<double> data, Color lineColor, bool fill) {
      final points = List.generate(
        data.length,
        (i) => Offset(
          i * size.width / (data.length - 1),
          size.height - data[i] / peak * size.height,
        ),
      );
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (var i = 1; i < points.length; i++) {
        final prev = points[i - 1];
        final next = points[i];
        final mid = (prev.dx + next.dx) / 2;
        path.cubicTo(mid, prev.dy, mid, next.dy, next.dx, next.dy);
      }
      if (fill) {
        final area = Path.from(path)
          ..lineTo(size.width, size.height)
          ..lineTo(0, size.height)
          ..close();
        canvas.drawPath(
          area,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                lineColor.withValues(alpha: .18),
                lineColor.withValues(alpha: .005),
              ],
            ).createShader(Offset.zero & size),
        );
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = lineColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = grid ? 2.4 : 1.8
          ..strokeCap = StrokeCap.round,
      );
    }

    draw(values, color, true);
    if (secondary != null) draw(secondary!, const Color(0xFF99B8DA), false);
  }

  @override
  bool shouldRepaint(covariant _ChartPainter oldDelegate) => true;
}

String region(String name) {
  if (RegExp('香港|HK|Hong Kong', caseSensitive: false).hasMatch(name)) {
    return 'HK';
  }
  if (RegExp('日本|JP|Tokyo|Osaka', caseSensitive: false).hasMatch(name)) {
    return 'JP';
  }
  if (RegExp('新加坡|SG|Singapore', caseSensitive: false).hasMatch(name)) {
    return 'SG';
  }
  if (RegExp(
    '美国|US|Los Angeles|San Jose',
    caseSensitive: false,
  ).hasMatch(name)) {
    return 'US';
  }
  if (RegExp('台湾|TW', caseSensitive: false).hasMatch(name)) return 'TW';
  return name == 'DIRECT' ? '直连' : 'AUTO';
}

class RegionIcon extends StatelessWidget {
  const RegionIcon(this.name, {super.key});
  final String name;
  @override
  Widget build(BuildContext context) {
    final code = region(name);
    final color = switch (code) {
      'HK' => const Color(0xFFE86B6B),
      'JP' => const Color(0xFFC2667A),
      'SG' => const Color(0xFFCF915D),
      'US' => const Color(0xFF668EBF),
      _ => context.accent,
    };
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(11),
      ),
      child: code == 'AUTO'
          ? Icon(Icons.auto_awesome_rounded, size: 17, color: color)
          : Text(
              code,
              style: TextStyle(
                color: color,
                fontSize: code == '直连' ? 10 : 12,
                fontWeight: FontWeight.w800,
              ),
            ),
    );
  }
}
