import 'package:flutter/foundation.dart';

/// Working hours used to derive attendance status instead of asking the
/// administrator to pick one from a list.
///
/// Everything here works on Beijing time (UTC+8) so a device with a wrong time
/// zone still books the same business day as the rest of the app.
@immutable
class Shift {
  const Shift({
    required this.start,
    required this.end,
    required this.graceMinutes,
  });

  /// `HH:mm` local business clock.
  final String start;
  final String end;

  /// Minutes of tolerance after [start] before a check-in counts as late.
  final int graceMinutes;

  static const defaults = Shift(
    start: '09:00',
    end: '18:00',
    graceMinutes: 10,
  );

  factory Shift.fromSettings(Map<String, dynamic> settings) => Shift(
    start: _clean(settings['shiftStart']) ?? defaults.start,
    end: _clean(settings['shiftEnd']) ?? defaults.end,
    graceMinutes:
        int.tryParse(settings['shiftGrace']?.toString() ?? '') ??
        defaults.graceMinutes,
  );

  static String? _clean(Object? value) {
    final text = value?.toString().trim() ?? '';
    if (!RegExp(r'^\d{1,2}:\d{2}$').hasMatch(text)) return null;
    final parts = text.split(':');
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);
    if (hour > 23 || minute > 59) return null;
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  /// Clock time on the business (UTC+8) day.
  static String clock(DateTime at) {
    final business = at.toUtc().add(const Duration(hours: 8));
    return [
      business.hour.toString().padLeft(2, '0'),
      business.minute.toString().padLeft(2, '0'),
    ].join(':');
  }

  static int minutesOf(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return 0;
    return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
  }

  bool get valid => minutesOf(start) < minutesOf(end);

  /// Status implied by a check-in at [at].
  String statusForIn(DateTime at) =>
      minutesOf(clock(at)) > minutesOf(start) + graceMinutes ? '迟到' : '正常';

  /// Status implied by a check-out at [at]. A late check-in keeps priority so
  /// the day is not rewritten from 迟到 to 早退.
  String statusForOut(DateTime at, {String inStatus = '正常'}) {
    if (inStatus == '迟到') return '迟到';
    return minutesOf(clock(at)) < minutesOf(end) ? '早退' : '正常';
  }

  Map<String, dynamic> toSettings() => {
    'shiftStart': start,
    'shiftEnd': end,
    'shiftGrace': graceMinutes,
  };

  String get label => '$start–$end${graceMinutes == 0 ? '' : ' · 宽限 $graceMinutes 分'}';

  Shift copyWith({String? start, String? end, int? graceMinutes}) => Shift(
    start: start ?? this.start,
    end: end ?? this.end,
    graceMinutes: graceMinutes ?? this.graceMinutes,
  );
}

/// One-tap row state for the today roster.
enum RosterState { none, checkIn, complete, late, abnormal }
