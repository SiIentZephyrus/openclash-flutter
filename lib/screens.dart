import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'clash_api.dart';
import 'dashboard_controller.dart';
import 'app_theme.dart';
import 'models.dart';
import 'ui_components.dart';
import 'proxies_page.dart';
import 'app_notice.dart';
import 'providers_page.dart';
import 'delay_settings.dart';

class DashboardShell extends StatefulWidget {
  const DashboardShell({super.key, required this.controller});
  final DashboardController controller;
  @override
  State<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends State<DashboardShell>
    with WidgetsBindingObserver {
  int page = 0;
  static const labels = ['概览', '代理', '连接', '日志', '设置'];
  static const icons = [
    Icons.space_dashboard_outlined,
    Icons.hub_outlined,
    Icons.swap_calls_rounded,
    Icons.terminal_rounded,
    Icons.tune_rounded,
  ];
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    if (state != null) didChangeAppLifecycleState(state);
    unawaited(widget.controller.initialize());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      unawaited(widget.controller.setBackgrounded(true));
    } else if (state == AppLifecycleState.resumed) {
      unawaited(widget.controller.setBackgrounded(false));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller.updatesFor(DashboardSection.session),
    builder: (context, _) {
      final c = widget.controller;
      if (!c.initialized) {
        return Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  '正在读取控制器配置…',
                  style: TextStyle(color: context.muted, fontSize: 12),
                ),
              ],
            ),
          ),
        );
      }
      if (!c.hasProfile) {
        return Scaffold(
          appBar: AppBar(
            title: const Text(
              'OpenClash',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: SettingsPage(controller: c, requiredSetup: true),
              ),
            ),
          ),
        );
      }
      final wide = MediaQuery.sizeOf(context).width >= 900;
      Widget content() => switch (page) {
        0 => OverviewPage(
          controller: c,
          onProxies: () => setState(() => page = 1),
          onSettings: () => setState(() => page = 4),
        ),
        1 => ProxiesPage(key: ValueKey(c.sessionGeneration), controller: c),
        2 => ConnectionsPage(key: ValueKey(c.sessionGeneration), controller: c),
        3 => LogsPage(key: ValueKey(c.sessionGeneration), controller: c),
        _ => SettingsPage(controller: c),
      };
      final updates = switch (page) {
        0 => Listenable.merge([
          c.updatesFor(DashboardSection.overview),
          c.updatesFor(DashboardSection.proxies),
        ]),
        1 => c.updatesFor(DashboardSection.proxies),
        2 => c.updatesFor(DashboardSection.connections),
        3 => c.updatesFor(DashboardSection.logs),
        _ => c.updatesFor(DashboardSection.streams),
      };
      return Scaffold(
        appBar: AppBar(
          toolbarHeight: 76,
          titleSpacing: 22,
          title: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: context.accent,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  Icons.bolt_rounded,
                  color: context.colors.onPrimary,
                  size: 25,
                ),
              ),
              const SizedBox(width: 10),
              const Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'OpenClash',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.8,
                    ),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 18),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => setState(() => page = 4),
                child: Tag(
                  c.connecting
                      ? '连接中'
                      : c.connected
                      ? '已连接'
                      : '未连接',
                  color: c.connected ? context.accent : context.muted,
                  dot: true,
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Row(
            children: [
              if (wide)
                NavigationRail(
                  selectedIndex: page,
                  onDestinationSelected: (value) =>
                      setState(() => page = value),
                  backgroundColor: context.surface,
                  labelType: NavigationRailLabelType.all,
                  groupAlignment: -.7,
                  destinations: List.generate(
                    5,
                    (i) => NavigationRailDestination(
                      icon: Icon(icons[i]),
                      label: Text(labels[i]),
                    ),
                  ),
                ),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1000),
                    child: ListenableBuilder(
                      listenable: updates,
                      builder: (context, _) => content(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: wide
            ? null
            : Container(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: context.stroke)),
                ),
                child: NavigationBar(
                  selectedIndex: page,
                  onDestinationSelected: (value) =>
                      setState(() => page = value),
                  destinations: List.generate(
                    5,
                    (i) => NavigationDestination(
                      icon: Icon(icons[i], size: 23),
                      label: labels[i],
                    ),
                  ),
                ),
              ),
      );
    },
  );
}

class OverviewPage extends StatelessWidget {
  const OverviewPage({
    super.key,
    required this.controller,
    required this.onProxies,
    required this.onSettings,
  });
  final DashboardController controller;
  final VoidCallback onProxies, onSettings;
  @override
  Widget build(BuildContext context) {
    final c = controller;
    final group = c.groups.where((g) => g.type == 'Selector').firstOrNull;
    final selectedDelay = group == null ? null : c.delayFor(group.name);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        const Text(
          '你的网络，一目了然。',
          style: TextStyle(
            fontSize: 25,
            fontWeight: FontWeight.w800,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          '保持连接，让每一次访问都更顺畅',
          style: TextStyle(color: context.muted, fontSize: 12),
        ),
        const SizedBox(height: 22),
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF116E64), Color(0xFF133D3C)],
            ),
            borderRadius: BorderRadius.circular(23),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                      c.connected
                          ? Icons.router_rounded
                          : Icons.router_outlined,
                      color: const Color(0xFFB9EAD9),
                      size: 24,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      c.connected ? 'CONNECTED' : 'DISCONNECTED',
                      style: const TextStyle(
                        fontSize: 9,
                        letterSpacing: 1,
                        color: Color(0xFFC9E9DE),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Text(
                c.connected ? 'OpenClash 正在运行' : '连接你的 OpenClash',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                c.address,
                style: const TextStyle(fontSize: 11, color: Color(0xFFB3D3CE)),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      c.version,
                      style: const TextStyle(
                        color: Color(0xFFB3D3CE),
                        fontSize: 11,
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 36,
                    child: FilledButton.icon(
                      onPressed: c.connected ? onProxies : onSettings,
                      icon: Icon(
                        c.connected ? Icons.hub_outlined : Icons.add_rounded,
                        size: 15,
                      ),
                      label: Text(
                        c.connected ? '切换节点' : '连接设置',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFE1F4EB),
                        foregroundColor: const Color(0xFF15584F),
                        padding: const EdgeInsets.symmetric(horizontal: 13),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, box) => Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _Metric(
                title: '下载速度',
                value: formatBytes(c.down, rate: true),
                icon: Icons.south_rounded,
                color: context.accent,
                values: c.downloadHistory,
                width: (box.maxWidth - 12) / 2,
              ),
              _Metric(
                title: '上传速度',
                value: formatBytes(c.up, rate: true),
                icon: Icons.north_rounded,
                color: const Color(0xFF6D8FB6),
                values: c.uploadHistory,
                width: (box.maxWidth - 12) / 2,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Panel(
          child: Column(
            children: [
              SectionTitle(
                '实时流量',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Tag('↓ 下载'),
                    const SizedBox(width: 6),
                    const Tag('↑ 上传', color: Color(0xFF6D8FB6)),
                  ],
                ),
              ),
              SparkChart(
                values: c.downloadHistory,
                secondary: c.uploadHistory,
                large: true,
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '过去 40 次采样',
                    style: TextStyle(fontSize: 9, color: context.muted),
                  ),
                  Text(
                    '现在',
                    style: TextStyle(fontSize: 9, color: context.muted),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _SmallStat('总下载', formatBytes(c.downloadTotal)),
                  ),
                  Expanded(
                    child: _SmallStat('总上传', formatBytes(c.uploadTotal)),
                  ),
                  Expanded(
                    child: _SmallStat('活跃连接', '${c.connections.length}'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SectionTitle(
          '当前代理',
          trailing: TextButton(
            onPressed: onProxies,
            child: const Text('全部策略组  →', style: TextStyle(fontSize: 11)),
          ),
        ),
        if (group != null)
          Panel(
            child: InkWell(
              onTap: onProxies,
              child: Row(
                children: [
                  RegionIcon(group.now),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group.now,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${group.name} · ${c.proxies[group.now]?.type ?? 'Proxy'}',
                          style: TextStyle(color: context.muted, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                  Tag(
                    c.delayErrorFor(group.name) != null
                        ? '失败'
                        : selectedDelay == null
                        ? '未测速'
                        : selectedDelay == 0
                        ? '超时'
                        : '$selectedDelay ms',
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.chevron_right_rounded, color: context.muted),
                ],
              ),
            ),
          )
        else
          const Panel(
            child: EmptyState(
              '尚未加载代理',
              '请先在设置中连接控制器',
              icon: Icons.hub_outlined,
            ),
          ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.memory_rounded, size: 13, color: context.muted),
            const SizedBox(width: 5),
            Text(
              '内存 ${formatBytes(c.memory)}  ·  ${c.nodeCount} 个节点',
              style: TextStyle(fontSize: 10, color: context.muted),
            ),
          ],
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.values,
    required this.width,
  });
  final String title, value;
  final IconData icon;
  final Color color;
  final List<double> values;
  final double width;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Panel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Text(title, style: TextStyle(color: context.muted, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 12),
          FittedBox(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -.8,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SparkChart(values: values, color: color),
        ],
      ),
    ),
  );
}

class _SmallStat extends StatelessWidget {
  const _SmallStat(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: TextStyle(color: context.muted, fontSize: 10)),
      const SizedBox(height: 6),
      Text(
        value,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
    ],
  );
}

class LogsPage extends StatefulWidget {
  const LogsPage({super.key, required this.controller});
  final DashboardController controller;
  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  static const logExport = MethodChannel('openclash/log_export');
  String query = '', level = 'all';
  bool paused = false, follow = true;
  bool pausedForSearch = false;
  bool exporting = false;
  List<LogEntry> frozen = [];
  final search = TextEditingController();
  final scroll = ScrollController();

  Future<void> exportLogs(String action, List<LogEntry> entries) async {
    if (entries.isEmpty || exporting) return;
    setState(() => exporting = true);
    final text = '${entries.map((entry) => entry.line).join('\n')}\n';
    try {
      await runAction(context, () async {
        bool? done;
        try {
          done = await logExport.invokeMethod<bool>(action, {'text': text});
        } on PlatformException catch (error) {
          throw ApiException(error.message ?? '日志导出失败');
        }
        if (action == 'save' && done == true && mounted) {
          showAppNotice(
            context,
            const AppNotice(title: '日志已保存', tone: NoticeTone.success),
          );
        }
      });
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  void updateQuery(String value) => setState(() {
    final wasSearching = query.trim().isNotEmpty;
    query = value;
    if (!wasSearching && query.trim().isNotEmpty && !paused) {
      frozen = List.of(widget.controller.logs);
      paused = pausedForSearch = true;
    } else if (query.trim().isEmpty && pausedForSearch) {
      paused = pausedForSearch = false;
      frozen = [];
    }
  });

  @override
  void dispose() {
    search.dispose();
    scroll.dispose();
    super.dispose();
  }

  List<LogEntry> get filtered => (paused ? frozen : widget.controller.logs)
      .where(
        (l) =>
            (level == 'all' || l.level == level) &&
            l.message.toLowerCase().contains(query.trim().toLowerCase()),
      )
      .toList();
  @override
  Widget build(BuildContext context) {
    final entries = filtered;
    if (follow && !paused && query.trim().isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            follow &&
            !paused &&
            query.trim().isEmpty &&
            scroll.hasClients) {
          scroll.jumpTo(scroll.position.maxScrollExtent);
        }
      });
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '实时日志',
                  style: TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                  ),
                ),
              ),
              Tag(
                paused
                    ? (pausedForSearch ? '搜索已暂停刷新' : '已暂停')
                    : widget.controller.liveStreams.contains('/logs')
                    ? '实时推送'
                    : '等待连接',
                color: paused ? context.muted : context.accent,
                dot: true,
              ),
              if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
                PopupMenuButton<String>(
                  tooltip: '导出筛选日志',
                  enabled: entries.isNotEmpty && !exporting,
                  icon: const Icon(Icons.ios_share_rounded, size: 20),
                  onSelected: (action) => exportLogs(action, filtered),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'save', child: Text('保存为文本文件')),
                    PopupMenuItem(value: 'share', child: Text('分享日志文件')),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            '每一次连接，都有迹可循',
            style: TextStyle(color: context.muted, fontSize: 12),
          ),
          const SizedBox(height: 18),
          TextField(
            key: const ValueKey('log-search'),
            controller: search,
            onChanged: updateQuery,
            decoration: InputDecoration(
              hintText: '搜索域名、IP 或日志内容',
              prefixIcon: Icon(
                Icons.search_rounded,
                size: 20,
                color: context.muted,
              ),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清空搜索',
                      onPressed: () {
                        search.clear();
                        updateQuery('');
                      },
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ['all', 'info', 'warning', 'error', 'debug']
                  .map(
                    (l) => Padding(
                      padding: const EdgeInsets.only(right: 7),
                      child: ChoiceChip(
                        label: Text(
                          l == 'all' ? '全部' : l.toUpperCase(),
                          style: const TextStyle(fontSize: 10),
                        ),
                        selected: level == l,
                        onSelected: (_) => setState(() => level = l),
                        showCheckmark: false,
                        selectedColor: context.selectedSurface,
                        backgroundColor: context.surface,
                        side: BorderSide(
                          color: level == l
                              ? context.accent.withValues(alpha: .3)
                              : context.stroke,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(9),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          Row(
            children: [
              Text(
                '${entries.length} 条记录',
                style: TextStyle(fontSize: 10, color: context.muted),
              ),
              const Spacer(),
              if (paused)
                IconButton(
                  tooltip: '刷新日志快照',
                  onPressed: () => setState(() {
                    frozen = List.of(widget.controller.logs);
                  }),
                  icon: Icon(
                    Icons.refresh_rounded,
                    size: 19,
                    color: context.accent,
                  ),
                ),
              IconButton(
                tooltip: paused ? '继续日志' : '暂停日志',
                onPressed: () => setState(() {
                  paused = !paused;
                  pausedForSearch = false;
                  if (paused) frozen = List.of(widget.controller.logs);
                  if (!paused) frozen = [];
                }),
                icon: Icon(
                  paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  size: 19,
                  color: context.accent,
                ),
              ),
              IconButton(
                tooltip: '复制筛选日志',
                onPressed: () => runAction(context, () async {
                  await Clipboard.setData(
                    ClipboardData(text: entries.map((e) => e.line).join('\n')),
                  );
                }, success: '日志已复制'),
                icon: Icon(
                  Icons.copy_all_outlined,
                  size: 18,
                  color: context.muted,
                ),
              ),
              IconButton(
                tooltip: '清空日志',
                onPressed: () {
                  widget.controller.clearLogs();
                  setState(() => frozen.clear());
                },
                icon: Icon(
                  Icons.delete_outline_rounded,
                  size: 19,
                  color: context.muted,
                ),
              ),
            ],
          ),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF172B2C),
                borderRadius: BorderRadius.circular(18),
              ),
              clipBehavior: Clip.antiAlias,
              child: entries.isEmpty
                  ? const Center(
                      child: Text(
                        '暂无匹配日志\n连接后将在这里实时显示',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF819D99),
                          height: 2,
                          fontSize: 12,
                        ),
                      ),
                    )
                  : ListView.separated(
                      controller: scroll,
                      padding: const EdgeInsets.all(14),
                      itemCount: entries.length,
                      separatorBuilder: (_, _) =>
                          const Divider(color: Color(0xFF243C3C), height: 20),
                      itemBuilder: (_, i) {
                        final log = entries[i];
                        final color = switch (log.level) {
                          'error' => const Color(0xFFF29C94),
                          'warning' => const Color(0xFFE8C47F),
                          'debug' => const Color(0xFF9AB1D6),
                          _ => const Color(0xFF86CFB7),
                        };
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  log.timestamp,
                                  style: const TextStyle(
                                    fontSize: 9,
                                    color: Color(0xFF829E98),
                                    fontFamily: 'monospace',
                                  ),
                                ),
                                const SizedBox(width: 9),
                                Text(
                                  log.level.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: color,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 7),
                            SelectableText(
                              log.message,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                color: Color(0xFFCCDBD7),
                                fontSize: 10,
                                height: 1.8,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ),
          Row(
            children: [
              Icon(Icons.circle, size: 5, color: context.accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '最多保留 1,500 条日志',
                  style: TextStyle(fontSize: 9, color: context.muted),
                ),
              ),
              Text(
                '跟随最新',
                style: TextStyle(fontSize: 10, color: context.muted),
              ),
              Transform.scale(
                scale: .7,
                child: Switch(
                  value: follow,
                  onChanged: (value) => setState(() => follow = value),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ConnectionsPage extends StatefulWidget {
  const ConnectionsPage({super.key, required this.controller});
  final DashboardController controller;
  @override
  State<ConnectionsPage> createState() => _ConnectionsPageState();
}

class _ConnectionsPageState extends State<ConnectionsPage> {
  String query = '';
  bool showRules = false;
  bool paused = false;
  List<Map<String, dynamic>> frozen = [];
  final search = TextEditingController();
  String? sourceDevice;
  String? policyGroup;
  bool closingAll = false;

  String deviceOf(Map<String, dynamic> item) =>
      '${(item['metadata'] as Map?)?['sourceIP'] ?? ''}';

  Iterable<String> chainOf(Map<String, dynamic> item) =>
      (item['chains'] as List? ?? const []).whereType<String>();

  Future<void> showFilters() async {
    final c = widget.controller;
    final items = paused ? frozen : source;
    final devices = {
      ?sourceDevice,
      ...items.map(deviceOf).where((device) => device.isNotEmpty),
    }.toList()..sort();
    final groups = {
      ?policyGroup,
      for (final item in items)
        ...chainOf(item).where((name) => c.proxies[name]?.isGroup == true),
    }.toList()..sort();
    var device = sourceDevice;
    var group = policyGroup;
    final result = await showDialog<(String?, String?)>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('筛选连接'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: device ?? '',
                decoration: const InputDecoration(labelText: '来源设备'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('全部设备')),
                  for (final name in devices)
                    DropdownMenuItem(
                      value: name,
                      child: Text(name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (value) => device = value == '' ? null : value,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: group ?? '',
                decoration: const InputDecoration(labelText: '策略组'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('全部策略组')),
                  for (final name in groups)
                    DropdownMenuItem(
                      value: name,
                      child: Text(name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (value) => group = value == '' ? null : value,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, (null, null)),
            child: const Text('清除筛选'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, (device, group)),
            child: const Text('应用'),
          ),
        ],
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      sourceDevice = result.$1;
      policyGroup = result.$2;
    });
  }

  Future<void> confirmCloseAll() async {
    final c = widget.controller;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('关闭全部连接？'),
        content: const Text('当前控制器上的所有活跃连接都将断开，包括筛选结果之外的连接。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('关闭全部'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true || closingAll) return;
    setState(() => closingAll = true);
    final closingIds = c.connections.map((item) => item['id']).toSet();
    await runAction(context, () async {
      await c.closeAllConnections();
      if (mounted) {
        setState(
          () => frozen.removeWhere((item) => closingIds.contains(item['id'])),
        );
      }
    }, success: '已关闭全部连接');
    if (mounted) setState(() => closingAll = false);
  }

  void showConnection(Map<String, dynamic> item, bool active) {
    final meta = item['metadata'] as Map? ?? const {};
    String address(Object? host, Object? port) {
      final value = host?.toString() ?? '';
      if (value.isEmpty) return '—';
      if (port == null || '$port'.isEmpty) return value;
      return '${value.contains(':') ? '[$value]' : value}:$port';
    }

    final host = meta['host']?.toString() ?? '';
    final ip = meta['destinationIP']?.toString() ?? '';
    final duration = widget.controller.connectionDuration(item, active: active);
    final details = <String, String>{
      '状态': active ? '活跃' : '已结束',
      '来源地址': address(meta['sourceIP'], meta['sourcePort']),
      '目标地址': address(host.isEmpty ? ip : host, meta['destinationPort']),
      if (host.isNotEmpty && ip.isNotEmpty && host != ip) '目标 IP': ip,
      '持续时间': duration == null ? '—' : '${duration.inSeconds} 秒',
      '命中规则': [
        item['rule'],
        item['rulePayload'],
      ].where((value) => value != null && '$value'.isNotEmpty).join(' · '),
      '代理链': chainOf(item).toList().reversed.join(' → '),
      '流量':
          '↓ ${formatBytes(item['download'] as num? ?? 0)}   ↑ ${formatBytes(item['upload'] as num? ?? 0)}',
    };
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          children: [
            Text('连接详情', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            for (final entry in details.entries)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(entry.key),
                subtitle: SelectableText(
                  entry.value.isEmpty ? '—' : entry.value,
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> get source => query.trim().isEmpty
      ? widget.controller.connections
      : widget.controller.recentConnections;

  List<Map<String, dynamic>> snapshot() =>
      source.map((item) => Map<String, dynamic>.of(item)).toList();

  void updateQuery(String value) => setState(() {
    query = value;
  });

  void selectTab(bool rules) => setState(() {
    if (showRules == rules) return;
    showRules = rules;
  });

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final liveConnectionIds = c.connections.map((item) => item['id']).toSet();
    final connections = (paused ? frozen : source)
        .where(
          (item) =>
              (sourceDevice == null || deviceOf(item) == sourceDevice) &&
              (policyGroup == null || chainOf(item).contains(policyGroup)) &&
              item.toString().toLowerCase().contains(
                query.trim().toLowerCase(),
              ),
        )
        .toList();
    final rules = c.rules
        .where(
          (item) => item.toString().toLowerCase().contains(
            query.trim().toLowerCase(),
          ),
        )
        .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '网络活动',
                style: TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                '查看连接去向与规则匹配',
                style: TextStyle(color: context.muted, fontSize: 12),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  ChoiceChip(
                    label: Text(
                      paused
                          ? '连接快照 ${frozen.length}'
                          : query.trim().isNotEmpty && !showRules
                          ? '近期连接 ${source.length}'
                          : '活跃连接 ${c.connections.length}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    selected: !showRules,
                    onSelected: (_) => selectTab(false),
                    showCheckmark: false,
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text(
                      '路由规则 ${c.rules.length}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    selected: showRules,
                    onSelected: (_) {
                      selectTab(true);
                      unawaited(c.loadRules());
                    },
                    showCheckmark: false,
                  ),
                  if (showRules) ...[
                    const Spacer(),
                    IconButton(
                      tooltip: '管理规则集',
                      onPressed: () =>
                          ProvidersPage.open(context, c, ProviderKind.rules),
                      icon: const Icon(Icons.inventory_2_outlined),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                key: const ValueKey('connection-search'),
                controller: search,
                onChanged: updateQuery,
                decoration: InputDecoration(
                  hintText: showRules ? '搜索规则、目标策略' : '搜索域名、IP、代理链',
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: context.muted,
                  ),
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '清空搜索',
                          onPressed: () {
                            search.clear();
                            updateQuery('');
                          },
                          icon: const Icon(Icons.close_rounded, size: 18),
                        ),
                ),
              ),
              if (!showRules)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        paused
                            ? '已暂停刷新'
                            : query.trim().isNotEmpty
                            ? '实时搜索 · 已结束保留 5 分钟'
                            : '实时刷新 · 搜索含最近 5 分钟连接',
                        style: TextStyle(fontSize: 10, color: context.muted),
                      ),
                    ),
                    if (paused)
                      IconButton(
                        tooltip: '刷新连接快照',
                        onPressed: () => setState(() => frozen = snapshot()),
                        icon: Icon(
                          Icons.refresh_rounded,
                          size: 19,
                          color: context.accent,
                        ),
                      ),
                    IconButton(
                      tooltip: '筛选连接',
                      onPressed: showFilters,
                      isSelected: sourceDevice != null || policyGroup != null,
                      selectedIcon: const Icon(
                        Icons.filter_alt_rounded,
                        size: 19,
                      ),
                      icon: const Icon(Icons.filter_alt_outlined, size: 19),
                    ),
                    IconButton(
                      tooltip: '关闭全部连接',
                      onPressed:
                          !c.connected || c.connections.isEmpty || closingAll
                          ? null
                          : confirmCloseAll,
                      icon: const Icon(Icons.link_off_rounded, size: 19),
                    ),
                    IconButton(
                      tooltip: paused ? '继续刷新连接' : '暂停刷新连接',
                      onPressed: () => setState(() {
                        paused = !paused;
                        frozen = paused ? snapshot() : [];
                      }),
                      icon: Icon(
                        paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                        size: 19,
                        color: context.accent,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            itemCount: (showRules ? rules.length : connections.length) + 1,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              if (i == (showRules ? rules.length : connections.length)) {
                return (showRules ? rules.isEmpty : connections.isEmpty)
                    ? EmptyState(
                        showRules
                            ? '暂无规则'
                            : paused
                            ? '暂无连接快照'
                            : query.trim().isNotEmpty
                            ? '暂无匹配连接'
                            : '暂无活跃连接',
                        query.isEmpty ? '连接控制器后自动更新' : '没有匹配的搜索结果',
                        icon: Icons.swap_calls_rounded,
                      )
                    : const SizedBox.shrink();
              }
              if (showRules) {
                final rule = rules[i];
                return Panel(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Tag('${rule['type']}'),
                          const Spacer(),
                          Text(
                            '${rule['proxy']}',
                            style: TextStyle(
                              color: context.accent,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${rule['payload']}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                );
              }
              final item = connections[i];
              final meta = item['metadata'] as Map<String, dynamic>? ?? {};
              final host = meta['host']?.toString();
              return Panel(
                key: ValueKey('connection-${item['id']}'),
                padding: const EdgeInsets.all(16),
                child: InkWell(
                  onTap: () => showConnection(
                    item,
                    liveConnectionIds.contains(item['id']),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.language_rounded,
                            size: 18,
                            color: context.accent,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              host?.isNotEmpty == true
                                  ? host!
                                  : '${meta['destinationIP'] ?? 'Unknown'}',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (!liveConnectionIds.contains(item['id']))
                            Tag('已结束', color: context.muted),
                          IconButton(
                            tooltip: '关闭连接',
                            visualDensity: VisualDensity.compact,
                            onPressed: !liveConnectionIds.contains(item['id'])
                                ? null
                                : () => runAction(context, () async {
                                    await c.closeConnection('${item['id']}');
                                    if (mounted) {
                                      setState(
                                        () => frozen.removeWhere(
                                          (entry) => entry['id'] == item['id'],
                                        ),
                                      );
                                    }
                                  }),
                            icon: Icon(
                              Icons.close_rounded,
                              size: 17,
                              color: context.muted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${meta['sourceIP'] ?? '—'} → :${meta['destinationPort'] ?? '—'} · ${meta['network'] ?? 'TCP'}',
                        style: TextStyle(color: context.muted, fontSize: 10),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        (item['chains'] as List? ?? []).reversed.join(' → '),
                        style: TextStyle(color: context.accent, fontSize: 10),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${item['rule'] ?? ''}',
                              style: TextStyle(
                                fontSize: 9,
                                color: context.muted,
                              ),
                            ),
                          ),
                          Text(
                            '↓ ${formatBytes(item['download'] as num? ?? 0)}   ↑ ${formatBytes(item['upload'] as num? ?? 0)}',
                            style: TextStyle(fontSize: 9, color: context.muted),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.controller,
    this.requiredSetup = false,
  });
  final bool requiredSetup;
  final DashboardController controller;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final form = GlobalKey<FormState>();
  late final address = TextEditingController(text: widget.controller.address);
  late final secret = TextEditingController(text: widget.controller.secret);
  late final name = TextEditingController(
    text: widget.controller.controllerName,
  );
  late bool editing = widget.requiredSetup;
  bool adding = false;
  bool visible = false;

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!editing && address.text != widget.controller.address) {
      _restoreFields();
      visible = false;
    }
  }

  @override
  void dispose() {
    if (editing && !widget.requiredSetup) {
      widget.controller.resumeAutoReconnect();
    }
    address.dispose();
    secret.dispose();
    name.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final notices = AppNoticeHost.maybeOf(context);
    final saved = await widget.controller.saveController(
      address.text,
      secret.text,
      name: name.text,
      add: adding,
    );
    if (saved) {
      if (mounted) cancelEdit();
      notices?.show(
        const AppNotice(
          title: '控制器已保存',
          message: '下次启动将自动连接，无需重复填写。',
          tone: NoticeTone.success,
        ),
      );
    }
  }

  void _restoreFields() {
    address.text = widget.controller.address;
    secret.text = widget.controller.secret;
    name.text = widget.controller.controllerName;
  }

  void cancelEdit() {
    _restoreFields();
    setState(() {
      editing = false;
      adding = false;
      visible = false;
    });
    widget.controller.resumeAutoReconnect();
  }

  void beginEdit() {
    widget.controller.pauseAutoReconnect();
    setState(() => editing = true);
  }

  Future<void> editDelaySettings() async {
    final c = widget.controller;
    final key = GlobalKey<FormState>();
    var url = c.delaySettings.url;
    var timeout = c.delaySettings.timeoutMs;
    final settings = await showDialog<DelaySettings>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('测速设置'),
        content: Form(
          key: key,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  initialValue: url,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: '默认测速地址'),
                  validator: (value) =>
                      DelaySettings.supportsUrl(value?.trim() ?? '')
                      ? null
                      : '请输入有效的 HTTP 或 HTTPS 地址',
                  onSaved: (value) => url = value!.trim(),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: '$timeout',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: '单节点超时（毫秒）'),
                  validator: (value) =>
                      DelaySettings.supportsTimeout(int.tryParse(value ?? ''))
                      ? null
                      : '请输入 250 到 30000 之间的整数',
                  onSaved: (value) => timeout = int.parse(value!),
                ),
                const SizedBox(height: 12),
                const Text('订阅集合已配置的测速地址会优先使用。'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, const DelaySettings()),
            child: const Text('恢复默认'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final form = key.currentState!;
              if (!form.validate()) return;
              form.save();
              Navigator.pop(
                dialog,
                DelaySettings(url: url, timeoutMs: timeout),
              );
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (!mounted || settings == null) return;
    await runAction(
      context,
      () => c.saveDelaySettings(settings),
      success: '测速设置已保存',
    );
  }

  Future<void> manageControllers() async {
    final c = widget.controller;
    final action = await showModalBottomSheet<(String, String)>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => FractionallySizedBox(
        heightFactor: .7,
        child: SafeArea(
          child: Column(
            children: [
              const Text(
                '控制器列表',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: c.savedControllers.length,
                  itemBuilder: (context, index) {
                    final profile = c.savedControllers[index];
                    final active = profile.address == c.address;
                    return ListTile(
                      leading: Icon(
                        active
                            ? Icons.check_circle_outline
                            : Icons.router_outlined,
                        color: context.accent,
                      ),
                      title: Text(profile.label),
                      subtitle: profile.name.isEmpty && !active
                          ? null
                          : Text(
                              active
                                  ? '当前控制器${profile.name.isEmpty ? '' : ' · ${profile.address}'}'
                                  : profile.address,
                            ),
                      onTap: active
                          ? null
                          : () => Navigator.pop(sheet, (
                              'switch',
                              profile.address,
                            )),
                      trailing: active
                          ? null
                          : IconButton(
                              tooltip: '删除 ${profile.label}',
                              icon: const Icon(Icons.delete_outline_rounded),
                              onPressed: () => Navigator.pop(sheet, (
                                'remove',
                                profile.address,
                              )),
                            ),
                    );
                  },
                ),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(sheet, ('add', '')),
                icon: const Icon(Icons.add_rounded),
                label: const Text('添加控制器'),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    final (kind, endpoint) = action;
    switch (kind) {
      case 'add':
        c.pauseAutoReconnect();
        address.clear();
        secret.clear();
        name.clear();
        setState(() {
          adding = editing = true;
          visible = false;
        });
      case 'switch':
        await runAction(context, () async {
          if (await c.switchController(endpoint) && mounted) cancelEdit();
        });
      case 'remove':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialog) => AlertDialog(
            title: const Text('删除此控制器？'),
            content: Text(endpoint),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialog, true),
                child: const Text('删除'),
              ),
            ],
          ),
        );
        if (mounted && confirmed == true) {
          await runAction(context, () => c.removeController(endpoint));
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final busy = c.connecting || c.savingProfile;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        Text(
          widget.requiredSetup ? '连接你的控制器' : '设置',
          style: TextStyle(
            fontSize: 25,
            fontWeight: FontWeight.w800,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          widget.requiredSetup ? '首次使用请先配置，连接并保存后进入' : '保存常用控制器并快速切换',
          style: TextStyle(color: context.muted, fontSize: 12),
        ),
        if (!widget.requiredSetup) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              OutlinedButton.icon(
                onPressed: busy || editing ? null : manageControllers,
                icon: const Icon(Icons.router_outlined, size: 18),
                label: const Text('管理控制器'),
              ),
              OutlinedButton.icon(
                onPressed: editDelaySettings,
                icon: const Icon(Icons.speed_rounded, size: 18),
                label: const Text('测速设置'),
              ),
            ],
          ),
        ],
        const SizedBox(height: 22),
        Panel(
          child: Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionTitle(
                  editing || c.controllerName.isEmpty
                      ? '控制器'
                      : c.controllerName,
                  subtitle: '连接 OpenClash / Mihomo 的外部控制接口',
                  trailing: Icon(
                    Icons.router_outlined,
                    color: context.accent,
                    size: 22,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  '控制器地址',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  key: const ValueKey('controller-address'),
                  controller: address,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  enabled: editing && !busy,
                  style: const TextStyle(fontSize: 12),
                  decoration: const InputDecoration(
                    hintText: 'http://192.168.1.1:9090',
                  ),
                  validator: (value) {
                    try {
                      ClashApi.validateAddress(value ?? '');
                      return null;
                    } catch (_) {
                      return '请输入有效的 http:// 或 https:// 地址';
                    }
                  },
                ),
                const SizedBox(height: 18),
                const Text(
                  'API Secret',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  key: const ValueKey('controller-secret'),
                  controller: secret,
                  obscureText: !visible,
                  autocorrect: false,
                  enableSuggestions: false,
                  enabled: editing && !busy,
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                    hintText: '填写控制器密钥（未设置可留空）',
                    suffixIcon: IconButton(
                      tooltip: visible ? '隐藏密钥' : '显示密钥',
                      onPressed: () => setState(() => visible = !visible),
                      icon: Icon(
                        visible
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 18,
                        color: context.muted,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                if (editing) ...[
                  TextFormField(
                    key: const ValueKey('controller-name'),
                    controller: name,
                    enabled: !busy,
                    style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(hintText: '控制器名称（选填）'),
                  ),
                  const SizedBox(height: 10),
                ],
                Text(
                  '地址和密钥会加密保存在本机，下次启动自动使用。',
                  style: TextStyle(fontSize: 10, color: context.muted),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: busy
                        ? null
                        : () =>
                              runAction(context, editing ? save : c.reconnect),
                    icon: busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.link_rounded, size: 18),
                    label: Text(
                      c.savingProfile
                          ? '正在验证并保存…'
                          : c.connecting
                          ? '正在连接…'
                          : editing
                          ? (widget.requiredSetup ? '保存并进入' : '保存并连接')
                          : '重新连接',
                    ),
                  ),
                ),
                if (!widget.requiredSetup) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: c.savingProfile
                          ? null
                          : editing
                          ? cancelEdit
                          : beginEdit,
                      icon: Icon(
                        editing ? Icons.close_rounded : Icons.edit_outlined,
                        size: 16,
                      ),
                      label: Text(
                        editing ? (adding ? '取消添加' : '取消修改') : '修改控制器',
                      ),
                    ),
                  ),
                ],
                if (c.error != null) ...[
                  const SizedBox(height: 12),
                  AppNoticeCard(
                    notice: AppNotice(
                      title: '连接未成功',
                      message: c.error!,
                      tone: NoticeTone.error,
                    ),
                    floating: false,
                  ),
                ],
                if (c.connected) ...[
                  const SizedBox(height: 15),
                  Row(
                    children: [
                      const Tag('连接成功', dot: true),
                      const Spacer(),
                      Flexible(
                        child: Text(
                          c.version,
                          style: TextStyle(fontSize: 10, color: context.muted),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
                if (!widget.requiredSetup) ...[
                  const SizedBox(height: 16),
                  _ControllerDiagnostics(controller: c),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Panel(
          color: context.selectedSurface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.lightbulb_outline_rounded,
                    size: 18,
                    color: context.accent,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '如何连接 OpenClash？',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 13),
              Text(
                '1. 手机与路由器连接到同一局域网。\n2. 在 OpenClash 中查看外部控制器端口和密钥。\n3. 填写路由器 IP、控制器端口及 API Secret。',
                style: TextStyle(
                  fontSize: 11,
                  color: context.colors.onPrimaryContainer,
                  height: 2,
                ),
              ),
              const SizedBox(height: 9),
              Text(
                '这里填写控制器地址，而非 LuCI 管理页面地址。',
                style: TextStyle(fontSize: 10, color: context.muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 25),
        Center(
          child: Text(
            'OpenClash Mobile  1.1.0\nInspired by MetaCubeXD · Built with Flutter',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.muted, fontSize: 10, height: 2),
          ),
        ),
      ],
    );
  }
}

class _ControllerDiagnostics extends StatelessWidget {
  const _ControllerDiagnostics({required this.controller});
  final DashboardController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final status = switch (c.connectionFailure) {
      ApiFailure.authentication => '鉴权失败',
      ApiFailure.unreachable => '控制器地址不可达',
      ApiFailure.response => '控制接口异常',
      null =>
        c.connecting
            ? '正在连接'
            : c.connected
            ? '控制接口可用'
            : '尚未连接',
    };
    const channels = {
      '/traffic': '流量',
      '/memory': '内存',
      '/connections': '连接',
      '/logs': '日志',
    };
    final interrupted = channels.keys
        .where(c.interruptedStreams.contains)
        .map((path) => channels[path]!)
        .join('、');
    final last = c.lastConnected;
    final l10n = MaterialLocalizations.of(context);
    final lastTime = last == null
        ? '暂无'
        : '${l10n.formatShortDate(last)} ${l10n.formatTimeOfDay(TimeOfDay.fromDateTime(last), alwaysUse24HourFormat: true)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('连接诊断', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        Text(status),
        if (c.connected)
          Text(
            c.backgrounded
                ? '实时通道已暂停'
                : '实时通道 ${c.liveStreams.length}/${channels.length}${interrupted.isEmpty ? '' : ' · $interrupted通道中断，正在重试'}',
          ),
        Text('本次启动最近连接成功时间 $lastTime'),
      ],
    );
  }
}
