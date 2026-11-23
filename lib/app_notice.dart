import 'dart:async';
import 'package:flutter/material.dart';

enum NoticeTone {
  success(Color(0xFF087F72), Icons.check_rounded),
  error(Color(0xFFC25F59), Icons.close_rounded),
  warning(Color(0xFFAE8439), Icons.priority_high_rounded),
  info(Color(0xFF6089AE), Icons.info_outline_rounded);

  const NoticeTone(this.color, this.icon);
  final Color color;
  final IconData icon;
}

class NoticeMetric {
  const NoticeMetric(this.label, this.value, this.tone);
  final String label;
  final int value;
  final NoticeTone tone;
}

class AppNotice {
  const AppNotice({
    required this.title,
    this.message,
    this.tone = NoticeTone.info,
    this.metrics = const [],
    this.duration,
  });
  final String title;
  final String? message;
  final NoticeTone tone;
  final List<NoticeMetric> metrics;
  final Duration? duration;
}

void showAppNotice(BuildContext context, AppNotice notice) =>
    AppNoticeHost.maybeOf(context)?.show(notice);

/// A single, app-wide notice slot. New notices replace old ones, including
/// across page changes, without queuing stale messages or blocking input.
class AppNoticeHost extends StatefulWidget {
  const AppNoticeHost({super.key, required this.child});
  final Widget child;
  static AppNoticeHostState? maybeOf(BuildContext context) =>
      context.findAncestorStateOfType<AppNoticeHostState>();
  @override
  State<AppNoticeHost> createState() => AppNoticeHostState();
}

class AppNoticeHostState extends State<AppNoticeHost> {
  AppNotice? _notice;
  Timer? _timer;
  int _serial = 0;

  void show(AppNotice notice) {
    if (!mounted) return;
    _timer?.cancel();
    final serial = ++_serial;
    setState(() => _notice = notice);
    final duration =
        notice.duration ??
        Duration(
          seconds: notice.metrics.isNotEmpty
              ? 6
              : notice.tone == NoticeTone.error
              ? 6
              : notice.tone == NoticeTone.success
              ? 3
              : 4,
        );
    _timer = Timer(duration, () => dismiss(serial));
  }

  void dismiss([int? serial]) {
    if (!mounted || (serial != null && serial != _serial)) return;
    _timer?.cancel();
    setState(() => _notice = null);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notice = _notice;
    final serial = _serial;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        Positioned(
          top: MediaQuery.paddingOf(context).top + 10,
          left: 16,
          right: 16,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: AnimatedSwitcher(
                duration: Duration(milliseconds: reduceMotion ? 0 : 220),
                reverseDuration: Duration(milliseconds: reduceMotion ? 0 : 150),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, -.16),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: notice == null
                    ? const SizedBox.shrink(key: ValueKey('notice-empty'))
                    : Dismissible(
                        key: ValueKey('app-notice-$serial'),
                        direction: DismissDirection.horizontal,
                        resizeDuration: null,
                        onDismissed: (_) => dismiss(serial),
                        child: Semantics(
                          container: true,
                          liveRegion: true,
                          child: AppNoticeCard(
                            notice: notice,
                            onClose: () => dismiss(serial),
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Also used inline for form errors, where the message must stay visible.
class AppNoticeCard extends StatelessWidget {
  const AppNoticeCard({
    super.key,
    required this.notice,
    this.onClose,
    this.floating = true,
  });
  final AppNotice notice;
  final VoidCallback? onClose;
  final bool floating;

  @override
  Widget build(BuildContext context) {
    final color = notice.tone.color;
    return Material(
      type: MaterialType.transparency,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(floating ? 19 : 13),
          border: Border.all(color: color.withValues(alpha: .16)),
          boxShadow: floating
              ? [
                  BoxShadow(
                    color: const Color(0xFF183D35).withValues(alpha: .10),
                    blurRadius: 24,
                    offset: const Offset(0, 7),
                  ),
                ]
              : null,
        ),
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .09),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(notice.tone.icon, color: color, size: 21),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    notice.title,
                    style: const TextStyle(
                      color: Color(0xFF18312F),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      height: 1.4,
                    ),
                  ),
                  if (notice.message?.isNotEmpty == true) ...[
                    const SizedBox(height: 4),
                    Text(
                      notice.message!,
                      style: const TextStyle(
                        color: Color(0xFF728681),
                        fontSize: 11,
                        height: 1.65,
                      ),
                    ),
                  ],
                  if (notice.metrics.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final metric in notice.metrics)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: metric.tone.color.withValues(alpha: .07),
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: '${metric.label}  ',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                  TextSpan(
                                    text: '${metric.value}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              style: TextStyle(
                                color: metric.tone.color,
                                fontSize: 10,
                                height: 1.3,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (onClose != null) ...[
              const SizedBox(width: 4),
              Semantics(
                label: '关闭提示',
                button: true,
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: IconButton(
                    key: const ValueKey('dismiss-app-notice'),
                    onPressed: onClose,
                    padding: EdgeInsets.zero,
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: Color(0xFF94A59F),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class TaskProgressNotice extends StatelessWidget {
  const TaskProgressNotice({
    super.key,
    required this.title,
    required this.completed,
    required this.total,
    this.onCancel,
  });
  final String title;
  final int completed, total;
  final VoidCallback? onCancel;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: const Color(0xFFECF5F1),
      borderRadius: BorderRadius.circular(12),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    child: Column(
      children: [
        Row(
          children: [
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.7),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF267C67),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              '$completed/$total',
              key: const ValueKey('latency-progress'),
              style: const TextStyle(color: Color(0xFF267C67), fontSize: 10),
            ),
            if (onCancel != null) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: onCancel,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('取消测速'),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: total == 0 ? 0 : (completed / total).clamp(0, 1),
          minHeight: 3,
          backgroundColor: const Color(0xFFD8EAE2),
          color: const Color(0xFF358D77),
          borderRadius: BorderRadius.circular(3),
        ),
      ],
    ),
  );
}
