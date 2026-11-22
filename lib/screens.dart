import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'clash_api.dart';
import 'dashboard_controller.dart';
import 'main.dart';
import 'models.dart';
import 'ui_components.dart';
import 'proxies_page.dart';
import 'app_notice.dart';

class DashboardShell extends StatefulWidget {
  const DashboardShell({super.key, required this.controller});
  final DashboardController controller;
  @override
  State<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends State<DashboardShell> {
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
    unawaited(widget.controller.initialize());
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      if (!c.initialized) {
        return const Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text(
                  '正在读取控制器配置…',
                  style: TextStyle(color: muted, fontSize: 12),
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
      final content = [
        OverviewPage(
          controller: c,
          onProxies: () => setState(() => page = 1),
          onSettings: () => setState(() => page = 4),
        ),
        ProxiesPage(controller: c),
        ConnectionsPage(controller: c),
        LogsPage(controller: c),
        SettingsPage(controller: c),
      ][page];
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
                  color: accent,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.bolt_rounded,
                  color: Colors.white,
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
                  color: c.connected ? accent : muted,
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
                  backgroundColor: Colors.white,
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
                    child: content,
                  ),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: wide
            ? null
            : Container(
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: stroke)),
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
        const Text(
          '保持连接，让每一次访问都更顺畅',
          style: TextStyle(color: muted, fontSize: 12),
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
                color: accent,
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
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '过去 40 次采样',
                    style: TextStyle(fontSize: 9, color: muted),
                  ),
                  Text('现在', style: TextStyle(fontSize: 9, color: muted)),
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
                          style: const TextStyle(color: muted, fontSize: 10),
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
                  const Icon(Icons.chevron_right_rounded, color: muted),
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
            const Icon(Icons.memory_rounded, size: 13, color: muted),
            const SizedBox(width: 5),
            Text(
              '内存 ${formatBytes(c.memory)}  ·  ${c.nodeCount} 个节点',
              style: const TextStyle(fontSize: 10, color: muted),
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
              Text(title, style: const TextStyle(color: muted, fontSize: 11)),
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
      Text(label, style: const TextStyle(color: muted, fontSize: 10)),
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
  String query = '', level = 'all';
  bool paused = false, follow = true;
  List<LogEntry> frozen = [];
  final scroll = ScrollController();
  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  List<LogEntry> get filtered => (paused ? frozen : widget.controller.logs)
      .where(
        (l) =>
            (level == 'all' || l.level == level) &&
            l.message.toLowerCase().contains(query.toLowerCase()),
      )
      .toList();
  @override
  Widget build(BuildContext context) {
    final entries = filtered;
    if (follow && !paused) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && scroll.hasClients) {
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
                    ? '已暂停'
                    : widget.controller.liveStreams.contains('/logs')
                    ? '实时推送'
                    : '等待连接',
                color: paused ? muted : accent,
                dot: true,
              ),
            ],
          ),
          const SizedBox(height: 7),
          const Text(
            '每一次连接，都有迹可循',
            style: TextStyle(color: muted, fontSize: 12),
          ),
          const SizedBox(height: 18),
          TextField(
            onChanged: (v) => setState(() => query = v),
            decoration: const InputDecoration(
              hintText: '搜索域名、IP 或日志内容',
              prefixIcon: Icon(Icons.search_rounded, size: 20, color: muted),
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
                        selectedColor: const Color(0xFFDDF0E8),
                        backgroundColor: Colors.white,
                        side: BorderSide(
                          color: level == l
                              ? accent.withValues(alpha: .3)
                              : stroke,
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
                style: const TextStyle(fontSize: 10, color: muted),
              ),
              const Spacer(),
              IconButton(
                tooltip: paused ? '继续日志' : '暂停日志',
                onPressed: () => setState(() {
                  paused = !paused;
                  if (paused) frozen = List.of(widget.controller.logs);
                }),
                icon: Icon(
                  paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  size: 19,
                  color: accent,
                ),
              ),
              IconButton(
                tooltip: '复制筛选日志',
                onPressed: () => runAction(context, () async {
                  await Clipboard.setData(
                    ClipboardData(text: entries.map((e) => e.line).join('\n')),
                  );
                }, success: '日志已复制'),
                icon: const Icon(
                  Icons.copy_all_outlined,
                  size: 18,
                  color: muted,
                ),
              ),
              IconButton(
                tooltip: '清空日志',
                onPressed: () {
                  widget.controller.clearLogs();
                  setState(() => frozen.clear());
                },
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  size: 19,
                  color: muted,
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
              const Icon(Icons.circle, size: 5, color: accent),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  '最多保留 1,500 条日志',
                  style: TextStyle(fontSize: 9, color: muted),
                ),
              ),
              const Text('跟随最新', style: TextStyle(fontSize: 10, color: muted)),
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
  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final connections = c.connections
        .where(
          (item) => item.toString().toLowerCase().contains(query.toLowerCase()),
        )
        .toList();
    final rules = c.rules
        .where(
          (item) => item.toString().toLowerCase().contains(query.toLowerCase()),
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
              const Text(
                '查看连接去向与规则匹配',
                style: TextStyle(color: muted, fontSize: 12),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  ChoiceChip(
                    label: Text(
                      '活跃连接 ${c.connections.length}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    selected: !showRules,
                    onSelected: (_) => setState(() => showRules = false),
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
                      setState(() => showRules = true);
                      unawaited(c.loadRules());
                    },
                    showCheckmark: false,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                onChanged: (value) => setState(() => query = value),
                decoration: InputDecoration(
                  hintText: showRules ? '搜索规则、目标策略' : '搜索域名、IP、代理链',
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: muted,
                  ),
                ),
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
                        showRules ? '暂无规则' : '暂无活跃连接',
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
                            style: const TextStyle(color: accent, fontSize: 11),
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
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.language_rounded,
                          size: 18,
                          color: accent,
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
                        IconButton(
                          tooltip: '关闭连接',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => runAction(
                            context,
                            () => c.closeConnection('${item['id']}'),
                          ),
                          icon: const Icon(
                            Icons.close_rounded,
                            size: 17,
                            color: muted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${meta['sourceIP'] ?? '—'} → :${meta['destinationPort'] ?? '—'} · ${meta['network'] ?? 'TCP'}',
                      style: const TextStyle(color: muted, fontSize: 10),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      (item['chains'] as List? ?? []).reversed.join(' → '),
                      style: const TextStyle(color: accent, fontSize: 10),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${item['rule'] ?? ''}',
                            style: const TextStyle(fontSize: 9, color: muted),
                          ),
                        ),
                        Text(
                          '↓ ${formatBytes(item['download'] as num? ?? 0)}   ↑ ${formatBytes(item['upload'] as num? ?? 0)}',
                          style: const TextStyle(fontSize: 9, color: muted),
                        ),
                      ],
                    ),
                  ],
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
  late bool editing = widget.requiredSetup;
  bool visible = false;
  @override
  void dispose() {
    if (editing && !widget.requiredSetup) {
      widget.controller.resumeAutoReconnect();
    }
    address.dispose();
    secret.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final notices = AppNoticeHost.maybeOf(context);
    final saved = await widget.controller.saveController(
      address.text,
      secret.text,
    );
    if (saved) {
      if (mounted) setState(() => editing = false);
      notices?.show(
        const AppNotice(
          title: '控制器已保存',
          message: '下次启动将自动连接，无需重复填写。',
          tone: NoticeTone.success,
        ),
      );
    }
  }

  void cancelEdit() {
    address.text = widget.controller.address;
    secret.text = widget.controller.secret;
    setState(() {
      editing = false;
      visible = false;
    });
    widget.controller.resumeAutoReconnect();
  }

  void beginEdit() {
    widget.controller.pauseAutoReconnect();
    setState(() => editing = true);
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
          widget.requiredSetup ? '首次使用请先配置，连接并保存后进入' : '自动使用已保存配置，仅在手动修改后更换',
          style: TextStyle(color: muted, fontSize: 12),
        ),
        const SizedBox(height: 22),
        Panel(
          child: Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionTitle(
                  '控制器',
                  subtitle: '连接 OpenClash / Mihomo 的外部控制接口',
                  trailing: Icon(
                    Icons.router_outlined,
                    color: accent,
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
                        color: muted,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  '地址和密钥会加密保存在本机，下次启动自动使用。',
                  style: TextStyle(fontSize: 10, color: muted),
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
                      label: Text(editing ? '取消修改' : '修改控制器'),
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
                          style: const TextStyle(fontSize: 10, color: muted),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '实时通道 ${c.liveStreams.length}/4${c.liveStreams.length < 4 ? ' · 中断的通道会自动重连' : ' · 正常'}',
                    style: const TextStyle(fontSize: 10, color: muted),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        const Panel(
          color: Color(0xFFEDF4F1),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.lightbulb_outline_rounded,
                    size: 18,
                    color: accent,
                  ),
                  SizedBox(width: 8),
                  Text(
                    '如何连接 OpenClash？',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ],
              ),
              SizedBox(height: 13),
              Text(
                '1. 手机与路由器连接到同一局域网。\n2. 在 OpenClash 中查看外部控制器端口和密钥。\n3. 填写路由器 IP、控制器端口及 API Secret。',
                style: TextStyle(
                  fontSize: 11,
                  color: Color(0xFF607E75),
                  height: 2,
                ),
              ),
              SizedBox(height: 9),
              Text(
                '这里填写控制器地址，而非 LuCI 管理页面地址。',
                style: TextStyle(fontSize: 10, color: muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 25),
        const Center(
          child: Text(
            'OpenClash Mobile  1.0.5\nInspired by MetaCubeXD · Built with Flutter',
            textAlign: TextAlign.center,
            style: TextStyle(color: muted, fontSize: 10, height: 2),
          ),
        ),
      ],
    );
  }
}
