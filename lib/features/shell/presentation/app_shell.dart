import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import '../../../core/data/workspace.dart';
import '../../../core/reminders/notice_service.dart';
import '../../../core/theme/glass_spec.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../home/presentation/today_page.dart';
import '../../notice/presentation/notice_panel.dart';
import '../../records/presentation/records_page.dart';
import '../../sync/presentation/sync_page.dart';
import '../../settings/presentation/settings_page.dart';
import '../../update/presentation/update_panel.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.store, this.noticeSource});
  final Workspace store;

  /// Injectable notification transport so tests never touch the network.
  final NoticeSource? noticeSource;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int index = 0;
  int? pressed;
  bool slowDevice = false;
  bool _initializing = true;
  bool _syncing = false;
  int measuredFrames = 0, slowFrames = 0;
  bool _checking = false;
  DateTime? _lastDataSyncAt;
  Future<void>? _dataSyncInFlight;
  static const syncThrottle = Duration(minutes: 2);

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_frameTimings);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await _autoSync();
      } finally {
        if (mounted) setState(() => _initializing = false);
        // Notice sync can fail or be skipped; the update check still runs on
        // every cold start, after the first frame has settled.
        if (mounted) await _checkUpdates();
      }
    });
  }

  Future<void> _checkUpdates() async {
    if (!mounted || !widget.store.persistent) return;
    if (widget.store.settings['autoUpdate'] == false) return;
    await checkForUpdates(context, widget.store, automatic: true);
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

  /// One sync per cold start; after backgrounding, only when the app has been
  /// away longer than an hour, so request counts stay low.
  Future<void> _autoSync() async {
    if (_checking) return;
    if (widget.store.settings['autoSync'] == false) return;
    _checking = true;
    try {
      // A normal launch/resume round is a full pull-to-refresh: pending local
      // edits are pushed first, then the manifest and all changed business
      // shards (including people.json) are pulled. This keeps a second phone's
      // roster and attendance current without requiring the user to open Sync.
      await _requestDataSync(initial: true);
      final result = await syncNotices(
        widget.store,
        source: widget.noticeSource,
      );
      if (!mounted || !result.hasNews) return;
      await presentNoticeResult(context, widget.store, result);
    } finally {
      _checking = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_requestDataSync());
    }
  }

  Future<void> _requestDataSync({bool initial = false, bool manual = false}) {
    if (!manual && widget.store.settings['autoSync'] == false) {
      return Future<void>.value();
    }
    final active = _dataSyncInFlight;
    if (active != null) return active;
    final last = _lastDataSyncAt;
    if (!initial &&
        last != null &&
        DateTime.now().difference(last) < syncThrottle) {
      return Future<void>.value();
    }
    final future = _performDataSync(initial: initial);
    _dataSyncInFlight = future;
    return future.whenComplete(() => _dataSyncInFlight = null);
  }

  Future<void> _performDataSync({required bool initial}) async {
    if (!initial && mounted) setState(() => _syncing = true);
    try {
      final outcome = await widget.store.sync?.refresh();
      if (outcome != null && !outcome.ok) {
        widget.store.syncMessage = outcome.message;
      }
      _lastDataSyncAt = DateTime.now();
    } finally {
      if (!initial && mounted) setState(() => _syncing = false);
    }
  }

  final controller = PageController();
  final labels = const ['首页', '记录', '设置'];
  final icons = const [
    CupertinoIcons.house,
    CupertinoIcons.list_bullet,
    CupertinoIcons.gear,
  ];
  final activeIcons = const [
    CupertinoIcons.house_fill,
    CupertinoIcons.list_bullet,
    CupertinoIcons.gear,
  ];

  void select(int i) {
    if (index != i) HapticFeedback.selectionClick();
    setState(() => index = i);
    controller.animateToPage(
      i,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
              _initializing || _syncing
                  ? const Positioned.fill(child: SyncSkeletonPage())
                  : PageView(
                      controller: controller,
                      // The roster uses horizontal gestures (swipe to mark absent or
                      // leave), so tabs switch only from the capsule.
                      physics: const NeverScrollableScrollPhysics(),
                      onPageChanged: (i) => setState(() => index = i),
                      children: [
                        TodayPage(
                          store: widget.store,
                          onRefresh: () => _requestDataSync(manual: true),
                          onSync: () => select(2),
                          onSettings: () => select(2),
                          onRecords: () => select(1),
                        ),
                        RecordsPage(store: widget.store),
                        SettingsPage(
                          store: widget.store,
                          onSync: () => Navigator.of(context).push(
                            CupertinoPageRoute<void>(
                              builder: (_) => SyncPage(
                                store: widget.store,
                                onSettings: () => Navigator.of(context).pop(),
                                onStorageSettings: () =>
                                    Navigator.of(context).push(
                                      CupertinoPageRoute<void>(
                                        builder: (_) => SettingsPage(
                                          store: widget.store,
                                          section: '对象存储',
                                        ),
                                      ),
                                    ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
              // Keep the capsule mounted while the keyboard is open: hiding it
              // on an inset change made the layout jump behind modal panels.
              if (!_initializing)
                Positioned(
                  left: GlassSpec.navInset,
                  right: GlassSpec.navInset,
                  bottom:
                      MediaQuery.paddingOf(context).bottom +
                      GlassSpec.navBottomGap,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: GlassCard(
                        navigation: true,
                        radius: GlassSpec.navHeight / 2,
                        padding: const EdgeInsets.all(GlassSpec.indicatorInset),
                        child: SizedBox(
                          height: GlassSpec.navHeight - 8,
                          child: _navigation(),
                        ),
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
      final width = constraints.maxWidth / 3;
      void drag(DragUpdateDetails details) {
        if (!controller.hasClients) return;
        final page =
            ((controller.page ?? index.toDouble()) + details.delta.dx / width)
                .clamp(0.0, 2.0);
        controller.jumpTo(page * controller.position.viewportDimension);
      }

      void settle() {
        if (controller.hasClients) {
          select((controller.page ?? index.toDouble()).round());
        }
      }

      return GestureDetector(
        key: const ValueKey('bottom-navigation'),
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) {
          if (controller.hasClients) {
            controller.jumpTo(controller.offset);
          }
        },
        onHorizontalDragUpdate: drag,
        onHorizontalDragEnd: (_) => settle(),
        onHorizontalDragCancel: settle,
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final position =
                (controller.hasClients
                        ? controller.page ?? index.toDouble()
                        : index.toDouble())
                    .clamp(0.0, 2.0);
            return Stack(
              children: [
                Positioned(
                  left: width * position + GlassSpec.indicatorInset,
                  top: GlassSpec.indicatorInset,
                  bottom: GlassSpec.indicatorInset,
                  width: width - GlassSpec.indicatorInset * 2,
                  child: const GlassIndicator(
                    radius: GlassSpec.indicatorRadius,
                  ),
                ),
                Row(children: List.generate(3, (i) => _navItem(context, i))),
              ],
            );
          },
        ),
      );
    },
  );

  Widget _navItem(BuildContext context, int i) {
    final selected = index == i;
    final color = selected
        ? CupertinoColors.label.resolveFrom(context)
        : CupertinoColors.secondaryLabel.resolveFrom(context);
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: labels[i],
        child: Listener(
          onPointerDown: (_) => setState(() => pressed = i),
          onPointerUp: (_) {
            if (mounted) setState(() => pressed = null);
          },
          onPointerCancel: (_) {
            if (mounted) setState(() => pressed = null);
          },
          child: AnimatedScale(
            scale: pressed == i ? .94 : 1,
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              pressedOpacity: 1,
              onPressed: () => select(i),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    selected ? activeIcons[i] : icons[i],
                    size: 22,
                    color: color,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    labels[i],
                    style: TextStyle(
                      fontSize: 11,
                      color: color,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
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
}
