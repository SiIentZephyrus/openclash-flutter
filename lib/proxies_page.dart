import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dashboard_controller.dart';
import 'main.dart';
import 'models.dart';
import 'ui_components.dart';
import 'app_notice.dart';
import 'group_traffic.dart';

const _layouts = {'card': '卡片', 'list': '列表', 'compact': '紧凑'};

class ProxiesPage extends StatefulWidget {
  const ProxiesPage({super.key, required this.controller});
  final DashboardController controller;
  @override
  State<ProxiesPage> createState() => _ProxiesPageState();
}

class _ProxiesPageState extends State<ProxiesPage> {
  String query = '', searchScope = 'all', sort = 'default', layout = 'card';
  bool layoutChanged = false;
  final search = TextEditingController();
  final scroll = ScrollController();
  final Set<String> collapsed = {}, opened = {};
  final Set<String> revealed = {};
  final Map<String, GlobalKey> groupHeaders = {};
  double bottomPadding = 96;
  int jumpGeneration = 0;
  String? highlightedGroup;
  Timer? highlightTimer;
  DashboardController get c => widget.controller;

  List<ProxyNode> get _displayGroups {
    final groups = {for (final group in c.groups) group.name: group};
    for (final name in revealed) {
      final group = c.proxies[name];
      if (group != null && group.isGroup) groups.putIfAbsent(name, () => group);
    }
    return groups.values.toList();
  }

  Future<void> _afterLayout() {
    final binding = WidgetsBinding.instance;
    final frame = binding.endOfFrame;
    // endOfFrame alone does not schedule another frame when called during
    // post-frame callbacks. Filtering can leave the scroll offset unchanged.
    binding.scheduleFrame();
    return frame;
  }

  RenderBox? _boxFor(GlobalKey? key) {
    final element = key?.currentContext;
    // Keys may still reference an inactive element while filtering reparents
    // children. Inspect its render object directly, then require attachment.
    if (element is! RenderObjectElement) return null;
    final box = element.renderObject;
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    // A cached child can retain a size while its new sliver layout offset is
    // still null. Such a box cannot be used by getOffsetToReveal yet.
    RenderObject child = box;
    while (child.parent != null) {
      final parent = child.parent!;
      if (parent is RenderSliver && parent.childScrollOffset(child) == null) {
        return null;
      }
      if (parent is RenderAbstractViewport) return box;
      child = parent;
    }
    return null;
  }

  Future<void> _jumpToGroup(String name) async {
    final group = c.proxies[name];
    if (group == null || !group.isGroup) {
      showAppNotice(
        context,
        const AppNotice(
          title: '策略组暂不可用',
          message: '请刷新节点列表后重试',
          tone: NoticeTone.warning,
        ),
      );
      return;
    }
    final view = View.of(context);
    final notices = AppNoticeHost.maybeOf(context);
    FocusScope.of(context).unfocus();
    final generation = ++jumpGeneration;
    bool active() =>
        mounted && generation == jumpGeneration && scroll.hasClients;
    highlightTimer?.cancel();
    search.clear();
    setState(() {
      query = '';
      searchScope = 'all';
      revealed.add(name);
      collapsed.remove(name);
      opened.add(name);
      highlightedGroup = null;
    });
    // Clear filters and lay out the expanded target before reading its offset.
    await _afterLayout();
    if (!mounted || !active()) return;
    // Keyboard dismissal changes the viewport on Android. Finish it before
    // calculating an offset, rather than aligning against the old viewport.
    for (var frame = 0; frame < 30 && view.viewInsets.bottom > 0; frame++) {
      await _afterLayout();
      if (!mounted || !active()) return;
    }
    // Every group header participates in the sliver layout, while its grid
    // only builds visible nodes. The viewport can reveal even a distant header
    // directly, without visiting the groups in between.
    RenderBox? headerBox() => _boxFor(groupHeaders[name]);
    var aligned = false;
    var stableFrames = 0;
    for (var attempt = 0; attempt < 6; attempt++) {
      final box = headerBox();
      if (!active()) return;
      if (box == null) break;
      final viewport = RenderAbstractViewport.of(box);
      final target = viewport.getOffsetToReveal(box, 0).offset - 4;
      final shortfall = target - scroll.position.maxScrollExtent;
      if (shortfall > .5) {
        // A short final group needs enough trailing room to put its header
        // below the fixed search bar. Keep that room after highlight fades.
        setState(() => bottomPadding += shortfall + 1);
        await _afterLayout();
        if (!active()) return;
        continue;
      }
      final offset = target
          .clamp(
            scroll.position.minScrollExtent,
            scroll.position.maxScrollExtent,
          )
          .toDouble();
      if ((scroll.offset - offset).abs() <= .75) {
        if (++stableFrames >= 2) {
          aligned = true;
          break;
        }
        await _afterLayout();
        if (!active()) return;
        continue;
      }
      stableFrames = 0;
      scroll.jumpTo(offset);
      await _afterLayout();
      if (!active()) return;
    }
    if (!mounted || !active()) return;
    if (!aligned) {
      notices?.show(
        const AppNotice(
          title: '未能定位策略组',
          message: '请重试查看策略组',
          tone: NoticeTone.warning,
        ),
      );
      return;
    }
    setState(() => highlightedGroup = name);
    highlightTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => highlightedGroup = null);
    });
  }

  @override
  void initState() {
    super.initState();
    unawaited(_restoreLayout());
  }

  Future<void> _restoreLayout() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('proxyLayout');
    if (mounted && !layoutChanged && _layouts.containsKey(saved)) {
      setState(() => layout = saved!);
    }
  }

  Future<void> _setLayout(String value) async {
    layoutChanged = true;
    setState(() => layout = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('proxyLayout', value);
  }

  @override
  void dispose() {
    jumpGeneration++;
    highlightTimer?.cancel();
    search.dispose();
    scroll.dispose();
    super.dispose();
  }

  void _returnToTop() {
    FocusScope.of(context).unfocus();
    if (scroll.hasClients) {
      unawaited(
        scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  void _collapseAll() {
    setState(() {
      collapsed.addAll(_displayGroups.map((g) => g.name));
      opened.clear();
    });
    _returnToTop();
  }

  void _expandAll() => setState(() {
    collapsed.clear();
    opened.addAll(_displayGroups.map((g) => g.name));
  });
  bool _matchesGroup(ProxyNode g) =>
      g.name.toLowerCase().contains(query.trim().toLowerCase());
  bool _matchesNode(String name) =>
      name.toLowerCase().contains(query.trim().toLowerCase());
  bool _visibleGroup(ProxyNode group) =>
      query.trim().isEmpty ||
      switch (searchScope) {
        'groups' => _matchesGroup(group),
        'nodes' => group.members.any(_matchesNode),
        _ => _matchesGroup(group) || group.members.any(_matchesNode),
      };

  Future<void> _test(
    Future<void> Function() action,
  ) => runAction(context, () async {
    await action();
    if (mounted && c.testTotal > 0 && !c.testing) {
      final succeeded = c.testCompleted - c.testFailures - c.testTimeouts;
      showAppNotice(
        context,
        AppNotice(
          title: '测速完成',
          message:
              '已测试 ${c.testCompleted} 个节点${c.testFailures > 0 && c.delayErrors.isNotEmpty ? ' · ${c.delayErrors.values.first}' : ''}',
          tone: succeeded == 0
              ? NoticeTone.error
              : c.testFailures + c.testTimeouts > 0
              ? NoticeTone.warning
              : NoticeTone.success,
          metrics: [
            NoticeMetric('成功', succeeded, NoticeTone.success),
            NoticeMetric('超时', c.testTimeouts, NoticeTone.warning),
            NoticeMetric('失败', c.testFailures, NoticeTone.error),
          ],
        ),
      );
    }
  });

  void _showMenu() {
    FocusScope.of(context).unfocus();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: canvas,
      builder: (sheetContext) => SafeArea(
        child: ListenableBuilder(
          listenable: c,
          builder: (context, _) => SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Text(
                      '代理快捷操作',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.speed_rounded, color: accent),
                    title: const Text('测试所有节点延迟'),
                    subtitle: Text(
                      c.testing
                          ? '${c.testLabel} · ${c.testCompleted}/${c.testTotal}'
                          : '测试全部节点，不受搜索条件影响',
                      style: const TextStyle(fontSize: 10),
                    ),
                    enabled: !c.testing,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      unawaited(_test(c.testAllDelays));
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.layers_outlined, color: accent),
                    title: const Text('测试策略组延迟'),
                    subtitle: const Text(
                      '测试各策略组当前选中的路线',
                      style: TextStyle(fontSize: 10),
                    ),
                    enabled: !c.testing,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      unawaited(_test(c.testGroupDelays));
                    },
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.unfold_less_rounded),
                    title: const Text('全部收起'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _collapseAll();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.unfold_more_rounded),
                    title: const Text('全部展开'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _expandAll();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.vertical_align_top_rounded),
                    title: const Text('返回顶部'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _returnToTop();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.refresh_rounded),
                    title: const Text('刷新代理'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      unawaited(runAction(this.context, c.refresh));
                    },
                  ),
                  const Divider(),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(12, 4, 12, 10),
                    child: Text(
                      '页面布局',
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        for (final item in _layouts.entries)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ChoiceChip(
                                label: Text(
                                  item.value,
                                  style: const TextStyle(fontSize: 12),
                                ),
                                selected: layout == item.key,
                                onSelected: (_) {
                                  Navigator.pop(sheetContext);
                                  unawaited(_setLayout(item.key));
                                },
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final groups = _displayGroups;
    final visible = groups.where(_visibleGroup).toList();
    final nodeExtent = _nodeExtent(context);
    return Column(
      children: [
        // Search and its scope stay outside the scrollable proxy list.
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
          child: Column(
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '代理节点',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.8,
                      ),
                    ),
                  ),
                  Text(
                    query.trim().isEmpty
                        ? '${groups.length} 个策略组'
                        : '${visible.length} / ${groups.length} 个策略组',
                    style: const TextStyle(fontSize: 10, color: muted),
                  ),
                  PopupMenuButton<String>(
                    tooltip: '页面布局',
                    initialValue: layout,
                    onSelected: (value) => unawaited(_setLayout(value)),
                    icon: Icon(
                      switch (layout) {
                        'list' => Icons.view_list_rounded,
                        'compact' => Icons.view_agenda_outlined,
                        _ => Icons.grid_view_rounded,
                      },
                      size: 20,
                      color: accent,
                    ),
                    itemBuilder: (_) => [
                      for (final item in _layouts.entries)
                        PopupMenuItem(value: item.key, child: Text(item.value)),
                    ],
                  ),
                  PopupMenuButton<String>(
                    tooltip: '节点排序',
                    initialValue: sort,
                    onSelected: (value) => setState(() => sort = value),
                    icon: const Icon(
                      Icons.sort_rounded,
                      size: 21,
                      color: accent,
                    ),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'default', child: Text('默认排序')),
                      PopupMenuItem(value: 'delay', child: Text('延迟从低到高')),
                      PopupMenuItem(value: 'name', child: Text('名称排序')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),
              TextField(
                key: const ValueKey('proxy-search'),
                controller: search,
                onChanged: (value) => setState(() => query = value),
                decoration: InputDecoration(
                  hintText: switch (searchScope) {
                    'groups' => '搜索策略组名称',
                    'nodes' => '搜索节点名称或地区',
                    _ => '搜索节点、地区或策略组',
                  },
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: muted,
                  ),
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '清除搜索',
                          onPressed: () {
                            search.clear();
                            setState(() => query = '');
                          },
                          icon: const Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: muted,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final scope in const {
                            'all': '全部',
                            'groups': '策略组',
                            'nodes': '节点',
                          }.entries)
                            Padding(
                              padding: const EdgeInsets.only(right: 5),
                              child: ChoiceChip(
                                label: Text(
                                  scope.value,
                                  style: const TextStyle(fontSize: 10),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                ),
                                selected: searchScope == scope.key,
                                onSelected: (_) =>
                                    setState(() => searchScope = scope.key),
                                showCheckmark: false,
                                selectedColor: const Color(0xFFDFF0EA),
                                backgroundColor: Colors.white,
                                side: const BorderSide(color: stroke),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(9),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('collapse-all-groups'),
                    tooltip: '收起所有策略组',
                    onPressed: _collapseAll,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(
                      Icons.unfold_less_rounded,
                      size: 20,
                      color: accent,
                    ),
                  ),
                  IconButton(
                    tooltip: '展开所有策略组',
                    onPressed: _expandAll,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(
                      Icons.unfold_more_rounded,
                      size: 20,
                      color: accent,
                    ),
                  ),
                  IconButton(
                    tooltip: '返回顶部',
                    onPressed: _returnToTop,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(
                      Icons.vertical_align_top_rounded,
                      size: 20,
                      color: accent,
                    ),
                  ),
                ],
              ),
              if (c.testing) ...[
                TaskProgressNotice(
                  title: c.testLabel,
                  completed: c.testCompleted,
                  total: c.testTotal,
                ),
                const SizedBox(height: 6),
              ],
            ],
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: RefreshIndicator(
                  onRefresh: () => runAction(context, c.refresh),
                  child: CustomScrollView(
                    key: const ValueKey('proxy-list'),
                    controller: scroll,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                        sliver: SliverToBoxAdapter(
                          child: Column(
                            children: [
                              SizedBox(
                                width: double.infinity,
                                child: SegmentedButton<String>(
                                  segments: const [
                                    ButtonSegment(
                                      value: 'rule',
                                      label: Text(
                                        '规则',
                                        style: TextStyle(fontSize: 12),
                                      ),
                                      icon: Icon(
                                        Icons.alt_route_rounded,
                                        size: 15,
                                      ),
                                    ),
                                    ButtonSegment(
                                      value: 'global',
                                      label: Text(
                                        '全局',
                                        style: TextStyle(fontSize: 12),
                                      ),
                                      icon: Icon(
                                        Icons.public_rounded,
                                        size: 15,
                                      ),
                                    ),
                                    ButtonSegment(
                                      value: 'direct',
                                      label: Text(
                                        '直连',
                                        style: TextStyle(fontSize: 12),
                                      ),
                                      icon: Icon(Icons.east_rounded, size: 15),
                                    ),
                                  ],
                                  selected: {c.mode},
                                  showSelectedIcon: false,
                                  onSelectionChanged: c.connecting
                                      ? null
                                      : (value) => runAction(
                                          context,
                                          () => c.changeMode(value.first),
                                        ),
                                  style: SegmentedButton.styleFrom(
                                    side: const BorderSide(color: stroke),
                                    selectedBackgroundColor: const Color(
                                      0xFFDFF0EA,
                                    ),
                                    selectedForegroundColor: accent,
                                    backgroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              if (!c.connected)
                                Panel(
                                  child: EmptyState(
                                    c.connecting ? '正在连接…' : '控制器未连接',
                                    c.error ?? '前往设置添加路由器',
                                    icon: Icons.router_outlined,
                                  ),
                                ),
                              if (c.providerError != null)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: AppNoticeCard(
                                    notice: AppNotice(
                                      title: '订阅节点暂不可用',
                                      message: c.providerError!,
                                      tone: NoticeTone.warning,
                                    ),
                                    floating: false,
                                  ),
                                ),
                              if (groups.isEmpty && c.connected)
                                const Panel(
                                  child: EmptyState(
                                    '没有可用策略组',
                                    '请检查 OpenClash 配置中的 proxy-groups',
                                  ),
                                ),
                              if (query.trim().isNotEmpty && visible.isEmpty)
                                EmptyState(
                                  searchScope == 'groups'
                                      ? '没有匹配的策略组'
                                      : '没有匹配的节点',
                                  '试试其他名称或地区',
                                ),
                            ],
                          ),
                        ),
                      ),
                      for (final group in visible) _group(group, nodeExtent),
                      SliverToBoxAdapter(
                        child: SizedBox(height: bottomPadding),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                right: 20,
                bottom: 16,
                child: FloatingActionButton(
                  key: const ValueKey('proxy-floating-menu'),
                  heroTag: 'proxy-actions',
                  tooltip: '代理快捷菜单',
                  onPressed: _showMenu,
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                  child: const Icon(Icons.bolt_rounded),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Match the tile's single-line text metrics, including accessibility text
  // scaling. A fixed row extent lets SliverGrid know the exact scroll geometry
  // without building all preceding nodes.
  double _nodeExtent(BuildContext context) {
    double line(double size, [FontWeight? weight]) {
      final painter = TextPainter(
        text: TextSpan(
          text: '国Ag',
          style: DefaultTextStyle.of(
            context,
          ).style.merge(TextStyle(fontSize: size, fontWeight: weight)),
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final height = painter.height;
      painter.dispose();
      return height;
    }

    final nameHeight = line(layout == 'list' ? 12 : 11, FontWeight.w700);
    final badgeHeight = line(10, FontWeight.w600);
    final typeHeight = line(9);
    final contentHeight = switch (layout) {
      'list' =>
        24 + math.max(36, math.max(nameHeight + 5 + typeHeight, badgeHeight)),
      'compact' =>
        18 + math.max(16, nameHeight) + 4 + math.max(32, badgeHeight),
      _ =>
        24 +
            36 +
            10 +
            nameHeight +
            8 +
            math.max(14, math.max(typeHeight, badgeHeight)),
    };
    return contentHeight + 2;
  }

  Widget _group(ProxyNode group, double nodeExtent) {
    final isCollapsed =
        collapsed.contains(group.name) ||
        (group.type != 'Selector' &&
            !opened.contains(group.name) &&
            query.trim().isEmpty);
    // Do not filter/sort collapsed groups, or copy the members when the default
    // order and an empty query can use the original list directly.
    var names = const <String>[];
    if (!isCollapsed) {
      final showAll =
          query.trim().isEmpty ||
          searchScope == 'groups' ||
          (searchScope == 'all' && _matchesGroup(group));
      names = showAll
          ? group.members
          : group.members.where(_matchesNode).toList();
    }
    final sorted = sort == 'default' ? names : names.toList();
    if (sort == 'name') sorted.sort();
    if (sort == 'delay') {
      final delays = {for (final name in sorted) name: c.delayFor(name)};
      int value(String name) =>
          (delays[name] ?? 0) <= 0 ? 999999 : delays[name]!;
      sorted.sort((a, b) => value(a).compareTo(value(b)));
    }
    final header = InkWell(
      key: ValueKey('proxy-group-header-${group.name}'),
      borderRadius: BorderRadius.circular(20),
      onTap: () => setState(() {
        if (isCollapsed) {
          collapsed.remove(group.name);
          opened.add(group.name);
        } else {
          collapsed.add(group.name);
          opened.remove(group.name);
        }
      }),
      child: Padding(
        key: groupHeaders.putIfAbsent(group.name, GlobalKey.new),
        padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  group.type == 'Selector'
                      ? Icons.layers_outlined
                      : Icons.auto_awesome_rounded,
                  color: accent,
                  size: 20,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${group.members.length} 个 · ${group.now.isEmpty ? group.type : group.now}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 9, color: muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 5),
                _DelayBadge(controller: c, name: group.name, group: true),
                IconButton(
                  tooltip: '测试 ${group.name} 延迟',
                  onPressed: c.testing
                      ? null
                      : () => _test(() => c.testDelay(group)),
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(
                    Icons.speed_rounded,
                    color: accent,
                    size: 19,
                  ),
                ),
                Icon(
                  isCollapsed
                      ? Icons.keyboard_arrow_down_rounded
                      : Icons.keyboard_arrow_up_rounded,
                  color: muted,
                  size: 18,
                ),
              ],
            ),
            const SizedBox(height: 9),
            Padding(
              padding: const EdgeInsets.only(left: 29),
              child: _GroupTrafficStats(
                key: ValueKey('group-traffic-${group.name}'),
                name: group.name,
                rate: c.trafficFor(group.name),
              ),
            ),
          ],
        ),
      ),
    );
    return SliverPadding(
      key: ValueKey('proxy-group-${group.name}'),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      sliver: DecoratedSliver(
        decoration: BoxDecoration(
          color: highlightedGroup == group.name
              ? const Color(0xFFF1FAF6)
              : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: stroke),
        ),
        sliver: SliverMainAxisGroup(
          slivers: [
            SliverToBoxAdapter(child: header),
            if (!isCollapsed) ...[
              const SliverToBoxAdapter(
                child: Divider(height: 1, color: stroke),
              ),
              if (!group.selectable)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(12, 9, 12, 0),
                    child: Text(
                      '此策略组由内核自动分配节点',
                      style: TextStyle(color: muted, fontSize: 10),
                    ),
                  ),
                ),
              SliverPadding(
                key: ValueKey('proxy-members-${group.name}'),
                padding: const EdgeInsets.all(10),
                sliver: SliverLayoutBuilder(
                  builder: (context, constraints) {
                    final columns = layout == 'list'
                        ? 1
                        : constraints.crossAxisExtent > 650
                        ? 3
                        : 2;
                    return SliverGrid(
                      key: ValueKey('proxy-layout-$layout-${group.name}'),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: layout == 'compact' ? 6 : 8,
                        mainAxisExtent: nodeExtent,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => _node(group, sorted[index]),
                        childCount: sorted.length,
                        addAutomaticKeepAlives: false,
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _node(ProxyNode group, String name) => _NodeTile(
    key: ValueKey('proxy-node-${group.name}-$name'),
    node: c.proxies[name] ?? ProxyNode(name: name, type: 'Proxy'),
    controller: c,
    layout: layout,
    selected: group.now == name,
    enabled:
        !c.switching.contains(group.name) &&
        (group.selectable ||
            (group.now == name && c.proxies[name]?.isGroup == true)),
    onTap: () => runAction(
      context,
      () => group.now == name && c.proxies[name]?.isGroup == true
          ? _jumpToGroup(name)
          : c.select(group, name),
    ),
    onTest: () => _test(() => c.testNodeDelay(name)),
    onViewGroup: () => unawaited(runAction(context, () => _jumpToGroup(name))),
    groupName: group.name,
  );
}

class _GroupTrafficStats extends StatelessWidget {
  const _GroupTrafficStats({super.key, required this.name, required this.rate});
  final String name;
  final TrafficRate? rate;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: '按经过本策略组的活跃连接汇总上传、下载速率',
    child: Wrap(
      spacing: 12,
      runSpacing: 6,
      children: [
        for (final upload in [true, false])
          Semantics(
            label: '$name ${upload ? '上传' : '下载'}速率',
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: (upload ? accent : const Color(0xFF6089AE)).withValues(
                  alpha: .06,
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      upload ? Icons.north_rounded : Icons.south_rounded,
                      size: 12,
                      color: upload ? accent : const Color(0xFF6089AE),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      rate == null
                          ? '—'
                          : formatBytes(
                              upload ? rate!.upload : rate!.download,
                              rate: true,
                            ),
                      key: ValueKey(
                        'group-${upload ? 'upload' : 'download'}-$name',
                      ),
                      style: const TextStyle(fontSize: 10, color: ink),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _DelayBadge extends StatelessWidget {
  const _DelayBadge({
    required this.controller,
    required this.name,
    this.group = false,
  });
  final DashboardController controller;
  final String name;
  final bool group;
  @override
  Widget build(BuildContext context) {
    if (controller.testingNodes.contains(name)) {
      return const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 1.7),
      );
    }
    final error = controller.delayErrorFor(name);
    final delay = controller.delayFor(name);
    final testable = controller.canTest(name);
    final text = error != null
        ? '失败'
        : !testable
        ? (controller.proxies[name]?.type.toLowerCase() == 'direct'
              ? '直连'
              : '—')
        : delay == null
        ? '未测速'
        : delay == 0
        ? '超时'
        : '$delay ms';
    final color = error != null || delay == 0
        ? const Color(0xFFC37769)
        : delay == null
        ? muted
        : delay > 150
        ? const Color(0xFFB89248)
        : accent;
    return Tooltip(
      message: error ?? (group ? '策略组延迟；未单独测速时显示当前选中路线的延迟' : '节点连接延迟'),
      child: Text(
        text,
        key: ValueKey('${group ? 'group' : 'node'}-delay-$name'),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _NodeTile extends StatelessWidget {
  const _NodeTile({
    super.key,
    required this.node,
    required this.controller,
    required this.layout,
    required this.selected,
    required this.enabled,
    required this.onTap,
    required this.onTest,
    required this.onViewGroup,
    required this.groupName,
  });
  final ProxyNode node;
  final DashboardController controller;
  final String layout, groupName;
  final bool selected, enabled;
  final VoidCallback onTap, onTest, onViewGroup;

  @override
  Widget build(BuildContext context) {
    final name = Text(
      node.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: layout == 'list' ? 12 : 11,
        fontWeight: FontWeight.w700,
        color: selected ? accent : ink,
      ),
    );
    final selectedIcon = Icon(
      selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
      size: 16,
      color: selected ? accent : const Color(0xFFD5DEDC),
    );
    final badge = _DelayBadge(controller: controller, name: node.name);
    final test = SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        key: ValueKey('test-node-$groupName-${node.name}'),
        tooltip: '测试节点 ${node.name} 延迟',
        padding: EdgeInsets.zero,
        onPressed: !controller.canTest(node.name) || controller.testing
            ? null
            : onTest,
        icon: Icon(
          Icons.speed_rounded,
          size: 18,
          color: controller.testing || !controller.canTest(node.name)
              ? muted.withValues(alpha: .4)
              : accent,
        ),
      ),
    );
    final jump = SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        key: ValueKey('view-group-$groupName-${node.name}'),
        tooltip: '查看策略组 ${node.name}',
        padding: EdgeInsets.zero,
        icon: const Icon(Icons.shortcut_rounded, size: 18, color: accent),
        onPressed: onViewGroup,
      ),
    );
    return Semantics(
      selected: selected,
      button: true,
      label: '${node.name}${selected ? '，已选择' : ''}',
      hint: node.isGroup && selected ? '点击查看策略组' : null,
      child: Material(
        color: selected ? const Color(0xFFEDF8F3) : const Color(0xFFFAFBFB),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(13),
          side: BorderSide(
            color: selected ? accent : stroke,
            width: selected ? 1.4 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: EdgeInsets.all(layout == 'compact' ? 9 : 12),
            child: switch (layout) {
              'list' => Row(
                children: [
                  RegionIcon(node.name),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        name,
                        const SizedBox(height: 5),
                        Text(
                          node.type,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: muted, fontSize: 9),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  badge,
                  const SizedBox(width: 3),
                  test,
                  if (node.isGroup) jump,
                  selectedIcon,
                ],
              ),
              'compact' => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: name),
                      const SizedBox(width: 4),
                      selectedIcon,
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(child: badge),
                      test,
                      if (node.isGroup) jump,
                    ],
                  ),
                ],
              ),
              _ => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (node.isGroup)
                        const SizedBox(
                          width: 20,
                          height: 34,
                          child: Icon(
                            Icons.layers_outlined,
                            size: 18,
                            color: accent,
                          ),
                        )
                      else
                        RegionIcon(node.name),
                      const Spacer(),
                      test,
                      if (node.isGroup) jump,
                      selectedIcon,
                    ],
                  ),
                  const SizedBox(height: 10),
                  name,
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          node.type,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: muted, fontSize: 9),
                        ),
                      ),
                      const SizedBox(width: 4),
                      badge,
                    ],
                  ),
                ],
              ),
            },
          ),
        ),
      ),
    );
  }
}
