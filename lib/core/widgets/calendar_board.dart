import 'package:flutter/cupertino.dart';
import '../data/workspace.dart';
import '../theme/app_theme.dart';
import '../theme/design_tokens.dart';
import 'sheet.dart';

String dayKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

DateTime? parseDay(String? value) =>
    value == null || value.isEmpty ? null : DateTime.tryParse(value);

String monthKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}';

String prettyMonth(DateTime value) => '${value.year} 年 ${value.month} 月';

/// Days covered by [from]..[to], clipped to the inclusive range.
Iterable<DateTime> daysBetween(String from, String to) sync* {
  final start = parseDay(from);
  final end = parseDay(to);
  if (start == null || end == null) return;
  for (var d = DateTime(start.year, start.month, start.day);
      !d.isAfter(end);
      d = DateTime(d.year, d.month, d.day + 1)) {
    yield d;
  }
}

/// Month calendar with leave marks in red, single-day and range selection.
class CalendarBoard extends StatefulWidget {
  const CalendarBoard({
    super.key,
    this.initialMonth,
    this.selected = const {},
    this.marked = const {},
    this.rangeFrom,
    this.rangeTo,
    this.minDay,
    this.maxDay,
    this.onDayTap,
    this.onMonthChanged,
    this.today,
    this.showHeader = true,
    this.markedLegend = '请假',
  });
  final DateTime? initialMonth;
  final Set<String> selected;
  final Set<String> marked;
  final String? rangeFrom;
  final String? rangeTo;
  final String? minDay;
  final String? maxDay;
  final ValueChanged<String>? onDayTap;
  final ValueChanged<DateTime>? onMonthChanged;
  final String? today;
  final bool showHeader;
  final String? markedLegend;

  @override
  State<CalendarBoard> createState() => _CalendarBoardState();
}

class _CalendarBoardState extends State<CalendarBoard> {
  late DateTime month;
  static const weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  void initState() {
    super.initState();
    final base =
        widget.initialMonth ??
        parseDay(widget.today) ??
        DateTime.parse(businessToday());
    month = DateTime(base.year, base.month);
  }

  void shift(int delta) {
    setState(() => month = DateTime(month.year, month.month + delta));
    widget.onMonthChanged?.call(month);
  }

  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final today = widget.today ?? businessToday();
    final first = DateTime(month.year, month.month, 1);
    final total = DateTime(month.year, month.month + 1, 0).day;
    final lead = (first.weekday - 1) % 7;
    final cells = <Widget>[
      for (var i = 0; i < lead; i++) const SizedBox.shrink(),
      for (var d = 1; d <= total; d++)
        _dayCell(context, DateTime(month.year, month.month, d), today),
    ];
    while (cells.length % 7 != 0) {
      cells.add(const SizedBox.shrink());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showHeader) ...[
          Row(
            children: [
              _navButton(CupertinoIcons.chevron_left, () => shift(-1), '上一月'),
              Expanded(
                child: Center(
                  child: Text(
                    prettyMonth(month),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              _navButton(CupertinoIcons.chevron_right, () => shift(1), '下一月'),
            ],
          ),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            for (final label in weekdays)
              Expanded(
                child: Center(
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 11.5, color: secondary),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          mainAxisSpacing: 2,
          crossAxisSpacing: 2,
          childAspectRatio: 1,
          children: cells,
        ),
        if (widget.marked.isNotEmpty && widget.markedLegend != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: AppColors.leave.resolveFrom(context).withValues(
                      alpha: .22,
                    ),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  widget.markedLegend!,
                  style: TextStyle(fontSize: 11.5, color: secondary),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _navButton(IconData icon, VoidCallback onTap, String label) =>
      CupertinoButton(
        padding: const EdgeInsets.all(8),
        pressedOpacity: .5,
        onPressed: onTap,
        child: Icon(
          icon,
          size: 18,
          semanticLabel: label,
          color: CupertinoColors.secondaryLabel.resolveFrom(context),
        ),
      );

  Widget _dayCell(BuildContext context, DateTime date, String today) {
    final accent = CupertinoTheme.of(context).primaryColor;
    final dark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final key = dayKey(date);
    final isSelected = widget.selected.contains(key);
    final isMarked = widget.marked.contains(key);
    final isToday = key == today;
    final inRange =
        widget.rangeFrom != null &&
        widget.rangeTo != null &&
        key.compareTo(widget.rangeFrom!) >= 0 &&
        key.compareTo(widget.rangeTo!) <= 0;
    final disabled =
        (widget.minDay != null && key.compareTo(widget.minDay!) < 0) ||
        (widget.maxDay != null && key.compareTo(widget.maxDay!) > 0);
    final leave = AppColors.leave.resolveFrom(context);

    Color background = const Color(0x00000000);
    Color foreground = disabled
        ? CupertinoColors.tertiaryLabel.resolveFrom(context)
        : CupertinoColors.label.resolveFrom(context);
    Border? border;
    if (inRange) background = accent.withValues(alpha: dark ? .16 : .10);
    if (isMarked) {
      background = leave.withValues(alpha: dark ? .18 : .12);
      foreground = leave;
      border = Border.all(color: leave.withValues(alpha: .55), width: 1);
    }
    if (isSelected) {
      background = accent;
      foreground = CupertinoTheme.of(context).primaryContrastingColor;
      border = null;
    } else if (isToday) {
      border = Border.all(
        color: accent.withValues(alpha: .8),
        width: 1.2,
      );
    }

    final cell = Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(Radii.field),
        border: border,
      ),
      child: Text(
        '${date.day}',
        style: AppType.cell.copyWith(
          fontWeight: isSelected || isMarked
              ? FontWeight.w700
              : FontWeight.w500,
          color: foreground,
        ),
      ),
    );

    return Semantics(
      button: !disabled,
      selected: isSelected,
      label: '$key${isMarked ? ' 请假' : ''}',
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size(0, 0),
        pressedOpacity: .55,
        borderRadius: BorderRadius.circular(Radii.field),
        onPressed: disabled ? null : () => widget.onDayTap?.call(key),
        child: Padding(padding: const EdgeInsets.all(2), child: cell),
      ),
    );
  }
}

String businessToday() => businessDay();

/// Bottom-panel calendar used for backfill and leave dates.
Future<String?> showCalendarSheet(
  BuildContext context, {
  required String title,
  String? subtitle,
  String? initialDay,
  String? minDay,
  String? maxDay,
  Set<String> marked = const {},
  String confirmLabel = '确定',
}) async {
  var selected = initialDay;
  return showAppSheet<String>(
    context,
    (sheetContext) => StatefulBuilder(
      builder: (context, update) => SheetPanel(
        title: title,
        subtitle: subtitle,
        child: CalendarBoard(
          initialMonth: parseDay(selected),
          selected: {if (selected != null) selected!},
          marked: marked,
          minDay: minDay,
          maxDay: maxDay,
          onDayTap: (day) => update(() => selected = day),
        ),
        footer: _footer(
          context,
          confirmLabel: confirmLabel,
          onCancel: () => Navigator.of(sheetContext).pop(),
          onConfirm: selected == null
              ? null
              : () => Navigator.of(sheetContext).pop(selected),
        ),
      ),
    ),
  );
}

Widget _footer(  BuildContext context, {
  required String confirmLabel,
  required VoidCallback onCancel,
  required VoidCallback? onConfirm,
}) {
  final accent = CupertinoTheme.of(context).primaryColor;
  return Row(
    children: [
      Expanded(
        child: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: onCancel,
          child: const SizedBox(
            height: 52,
            child: Center(
              child: Text(
                '取消',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
            ),
          ),
        ),
      ),
      Expanded(
        child: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: onConfirm,
          child: SizedBox(
            height: 52,
            child: Center(
              child: Text(
                confirmLabel,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: onConfirm == null
                      ? CupertinoColors.tertiaryLabel.resolveFrom(context)
                      : accent,
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

/// Two-tap custom range picker used by the statistics filter.
Future<(String, String)?> showRangeSheet(
  BuildContext context, {
  String? from,
  String? to,
  String title = '自定义时间段',
  String? subtitle,
}) async {
  var start = from;
  var end = to;
  var expectingStart = start == null || end != null;
  return showAppSheet<(String, String)>(
    context,
    (sheetContext) => StatefulBuilder(
      builder: (context, update) => SheetPanel(
        title: title,
        subtitle:
            subtitle ??
            (start == null || end != null
                ? '点选开始日期'
                : '开始 ${start!}，请点选结束日期'),
        child: CalendarBoard(
          initialMonth: parseDay(start) ?? parseDay(end),
          rangeFrom: start,
          rangeTo: end,
          selected: {
            if (start != null) start!,
            if (end != null) end!,
          },
          onDayTap: (day) {
            update(() {
              if (expectingStart || start == null) {
                start = day;
                end = null;
                expectingStart = false;
              } else if (end == null) {
                if (day.compareTo(start!) < 0) {
                  end = start;
                  start = day;
                } else {
                  end = day;
                }
                expectingStart = true;
              } else {
                start = day;
                end = null;
                expectingStart = false;
              }
            });
          },
        ),
        footer: _footer(
          context,
          confirmLabel: '应用',
          onCancel: () => Navigator.of(sheetContext).pop(),
          onConfirm: start == null || end == null
              ? null
              : () => Navigator.of(sheetContext).pop((start!, end!)),
        ),
      ),
    ),
  );
}
