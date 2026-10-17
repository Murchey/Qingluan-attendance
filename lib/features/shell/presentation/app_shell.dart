import 'package:flutter/cupertino.dart';
import 'package:flutter/scheduler.dart';
import '../../../core/data/workspace.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../home/presentation/today_page.dart';
import '../../records/presentation/records_page.dart';
import '../../sync/presentation/sync_page.dart';
import '../../settings/presentation/settings_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.store});
  final Workspace store;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int index = 0;
  bool slowDevice = false;
  int measuredFrames = 0, slowFrames = 0;
  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_frameTimings);
  }

  void _frameTimings(List<FrameTiming> timings) {
    if (slowDevice || measuredFrames >= 90) return;
    // Ignore initial shader / engine startup, then sample sustained raster cost.
    for (final frame in timings) {
      measuredFrames++;
      if (measuredFrames > 30 && frame.rasterDuration.inMilliseconds > 24) {
        slowFrames++;
      }
    }
    if (measuredFrames >= 90 && slowFrames >= 15 && mounted) {
      setState(() => slowDevice = true);
    }
  }

  final controller = PageController();
  final labels = const ['今日', '记录', '同步', '设置'];
  final icons = const [
    CupertinoIcons.house,
    CupertinoIcons.list_bullet,
    CupertinoIcons.cloud,
    CupertinoIcons.gear,
  ];
  void select(int i) {
    setState(() => index = i);
    controller.animateToPage(
      i,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_frameTimings);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) => GlassScope(
        enabled: widget.store.settings['glass'] != false && !slowDevice,
        child: CupertinoPageScaffold(
          child: Stack(
            children: [
              const Positioned.fill(child: GlassBackdrop()),
              PageView(
                controller: controller,
                onPageChanged: (i) => setState(() => index = i),
                children: [
                  TodayPage(
                    store: widget.store,
                    onSync: () => select(2),
                    onSettings: () => select(3),
                    onRecords: () => select(1),
                  ),
                  RecordsPage(store: widget.store),
                  SyncPage(store: widget.store, onSettings: () => select(3)),
                  SettingsPage(store: widget.store),
                ],
              ),
              if (MediaQuery.viewInsetsOf(context).bottom == 0)
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: MediaQuery.paddingOf(context).bottom + 12,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: GlassCard(
                        navigation: true,
                        padding: const EdgeInsets.all(6),
                        child: SizedBox(height: 56, child: _navigation()),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navigation() => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth / 4;
      final dark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) {
          final next = (details.localPosition.dx / width).floor().clamp(0, 3);
          if (next != index) select(next);
        },
        child: Stack(
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 180),
              left: index * width,
              top: 0,
              bottom: 0,
              width: width,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: dark
                        ? const [Color(0x369BBDEB), Color(0x126F95CD)]
                        : const [Color(0x26819DBF), Color(0x12617EA5)],
                  ),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(
                    color: CupertinoColors.white.withValues(
                      alpha: dark ? .18 : .75,
                    ),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(
                        0xFF29486F,
                      ).withValues(alpha: dark ? .14 : .06),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
            Row(children: List.generate(4, (i) => _navItem(context, i))),
          ],
        ),
      );
    },
  );
  Widget _navItem(BuildContext context, int i) {
    final color = index == i
        ? CupertinoTheme.of(context).primaryColor
        : CupertinoColors.secondaryLabel.resolveFrom(context);
    return Expanded(
      child: Semantics(
        button: true,
        selected: index == i,
        label: labels[i],
        child: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => select(i),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icons[i], size: 21, color: color),
              Text(
                labels[i],
                style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: index == i ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
