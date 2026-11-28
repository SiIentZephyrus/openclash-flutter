import 'dart:async';
import 'package:flutter/material.dart';
import 'dashboard_controller.dart';
import 'models.dart';
import 'ui_components.dart';

class ProvidersPage extends StatefulWidget {
  const ProvidersPage({
    super.key,
    required this.controller,
    required this.kind,
  });

  final DashboardController controller;
  final ProviderKind kind;

  static void open(
    BuildContext context,
    DashboardController controller,
    ProviderKind kind,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProvidersPage(controller: controller, kind: kind),
      ),
    );
  }

  @override
  State<ProvidersPage> createState() => _ProvidersPageState();
}

class _ProvidersPageState extends State<ProvidersPage> {
  late var kind = widget.kind;
  bool loading = false;
  String? loadError;
  String? updating;
  final results = <(ProviderKind, String), (bool, String)>{};
  DashboardController get controller => widget.controller;
  late int generation = controller.sessionGeneration;

  @override
  void initState() {
    super.initState();
    generation = controller.sessionGeneration;
    controller.updatesFor(DashboardSection.session).addListener(sessionChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(load());
    });
  }

  void sessionChanged() {
    setState(() {
      if (generation == controller.sessionGeneration) return;
      generation = controller.sessionGeneration;
      loading = false;
      loadError = null;
      updating = null;
      results.clear();
    });
  }

  bool isCurrent(int previous) => mounted && previous == generation;

  Future<void> load() async {
    if (loading || updating != null) return;
    final previous = generation;
    setState(() {
      loading = true;
      loadError = null;
    });
    try {
      await controller.loadProviders(kind);
    } catch (error) {
      if (isCurrent(previous)) loadError = error.toString();
    } finally {
      if (isCurrent(previous)) setState(() => loading = false);
    }
  }

  Future<void> update(ProviderSummary provider) async {
    if (loading || updating != null) return;
    final previous = generation;
    final key = (provider.kind, provider.name);
    setState(() {
      updating = provider.name;
      results.remove(key);
    });
    try {
      await controller.updateProvider(provider);
      if (isCurrent(previous)) results[key] = (true, '更新成功');
    } catch (error) {
      if (isCurrent(previous)) results[key] = (false, error.toString());
    } finally {
      if (isCurrent(previous)) setState(() => updating = null);
    }
  }

  @override
  void dispose() {
    controller
        .updatesFor(DashboardSection.session)
        .removeListener(sessionChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('订阅与规则集'),
      actions: [
        IconButton(
          tooltip: '刷新集合列表',
          onPressed: controller.connected && !loading && updating == null
              ? load
              : null,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: SegmentedButton<ProviderKind>(
                  segments: [
                    for (final entry in ProviderKind.values)
                      ButtonSegment(value: entry, label: Text(entry.label)),
                  ],
                  selected: {kind},
                  onSelectionChanged: loading || updating != null
                      ? null
                      : (selection) {
                          setState(() => kind = selection.single);
                          unawaited(load());
                        },
                ),
              ),
              if (loading) const LinearProgressIndicator(),
              if (loadError != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    loadError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              Expanded(
                child: ListenableBuilder(
                  listenable: controller.updatesFor(DashboardSection.providers),
                  builder: (context, _) {
                    final entries = controller.providersFor(kind);
                    if (entries.isEmpty && !loading && loadError == null) {
                      return EmptyState(
                        controller.connected ? '暂无${kind.label}' : '控制器未连接',
                        controller.connected ? '请检查控制器配置' : '连接后可刷新集合列表',
                        icon: Icons.inventory_2_outlined,
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                      itemCount: entries.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final provider = entries[index];
                        final updatedAt = provider.updatedAt;
                        final result = results[(kind, provider.name)];
                        final localizations = MaterialLocalizations.of(context);
                        final description = [
                          if (provider.count != null)
                            '${provider.count} 条${kind.unit}',
                          if (updatedAt != null && updatedAt.year > 1)
                            '${localizations.formatShortDate(updatedAt)} ${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(updatedAt))}',
                          if (!provider.canUpdate) '由内核管理',
                        ].join(' · ');
                        return Panel(
                          padding: const EdgeInsets.all(6),
                          child: ListTile(
                            title: Text(provider.name),
                            subtitle: description.isEmpty && result == null
                                ? null
                                : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (description.isNotEmpty)
                                        Text(description),
                                      if (result != null)
                                        Text(
                                          result.$2,
                                          style: TextStyle(
                                            color: result.$1
                                                ? Theme.of(
                                                    context,
                                                  ).colorScheme.primary
                                                : Theme.of(
                                                    context,
                                                  ).colorScheme.error,
                                          ),
                                        ),
                                    ],
                                  ),
                            trailing: updating == provider.name
                                ? const SizedBox.square(
                                    dimension: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : IconButton(
                                    tooltip: '更新 ${provider.name}',
                                    onPressed:
                                        !controller.connected ||
                                            loading ||
                                            updating != null ||
                                            !provider.canUpdate
                                        ? null
                                        : () => update(provider),
                                    icon: const Icon(Icons.download_rounded),
                                  ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
