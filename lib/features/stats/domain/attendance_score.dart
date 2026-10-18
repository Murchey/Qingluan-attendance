import 'dart:math' as math;

import '../../../core/data/workspace.dart';

/// The attendance statuses that can cost points. "正常" and the leave status
/// stay free: leave is scored from the confirmed [Leave] interval instead, so a
/// single absence is never counted twice.
const scoreStatuses = ['迟到', '早退', '缺勤'];

/// Default deduction per leave day. A zero value means the leave type does not
/// affect the attendance score unless the workspace overrides it.
const defaultLeavePoints = <String, double>{
  '事假': 2,
  '病假': 1,
  '年假': 0,
  '调休': 0,
  '婚假': 0,
  '产假': 0,
  '其他': 1,
};

const defaultStatusPoints = <String, double>{'迟到': 2, '早退': 2, '缺勤': 5};

const defaultBaseScore = 100.0;

/// Compact point text: integers stay integers, decimals lose trailing zeros.
String scoreText(double value) {
  final rounded = (value * 100).roundToDouble() / 100;
  if (rounded == rounded.roundToDouble()) return rounded.toStringAsFixed(0);
  return rounded
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

double _points(Object? raw, double fallback, {double max = 100}) {
  final value = raw is num ? raw.toDouble() : double.tryParse('$raw');
  if (value == null || value.isNaN || value.isInfinite) return fallback;
  return value.clamp(0, max).toDouble();
}

/// Default deduction values for the attendance score. The rules live in
/// [Workspace.settings] under the scoreRules key, so they travel with the
/// workspace snapshot and never require a schema migration.
class ScoreRules {
  const ScoreRules({
    required this.base,
    required this.leave,
    required this.status,
  });

  factory ScoreRules.defaults() => ScoreRules(
    base: defaultBaseScore,
    leave: Map<String, double>.of(defaultLeavePoints),
    status: Map<String, double>.of(defaultStatusPoints),
  );

  /// Tolerates legacy or partially written maps: unknown leave types keep the
  /// built-in default, and values are clamped to 0..100.
  factory ScoreRules.fromSettings(Object? raw) {
    final json = raw is Map
        ? Map<String, dynamic>.from(raw)
        : const <String, dynamic>{};
    final leaveJson = json['leave'] is Map
        ? Map<String, dynamic>.from(json['leave'] as Map)
        : const <String, dynamic>{};
    final statusJson = json['status'] is Map
        ? Map<String, dynamic>.from(json['status'] as Map)
        : const <String, dynamic>{};
    return ScoreRules(
      base: _points(json['base'], defaultBaseScore, max: 1000),
      leave: {
        for (final entry in defaultLeavePoints.entries)
          entry.key: _points(leaveJson[entry.key], entry.value),
      },
      status: {
        for (final entry in defaultStatusPoints.entries)
          entry.key: _points(statusJson[entry.key], entry.value),
      },
    );
  }

  final double base;
  final Map<String, double> leave;
  final Map<String, double> status;

  double leavePoints(String type) => leave[type] ?? 0;
  double statusPoints(String status) => this.status[status] ?? 0;

  ScoreRules withBase(double value) => ScoreRules(
    base: value.clamp(0, 1000).toDouble(),
    leave: leave,
    status: status,
  );

  /// The kind argument is leave or status.
  ScoreRules withPoint(String kind, String key, double value) {
    final leave = Map<String, double>.of(this.leave);
    final status = Map<String, double>.of(this.status);
    if (kind == 'leave') {
      leave[key] = value.clamp(0, 100).toDouble();
    } else {
      status[key] = value.clamp(0, 100).toDouble();
    }
    return ScoreRules(base: base, leave: leave, status: status);
  }

  Map<String, dynamic> toJson() => {
    'base': base,
    'leave': leave,
    'status': status,
  };

  /// One-line settings summary, e.g. "事假 2 · 病假 1 · 迟到 2 · 缺勤 5 分".
  String get summary {
    final items = <String>[
      for (final type in ['事假', '病假'])
        if (leavePoints(type) > 0) '$type ${scoreText(leavePoints(type))}',
      for (final status in ['迟到', '缺勤'])
        if (statusPoints(status) > 0)
          '$status ${scoreText(statusPoints(status))}',
    ];
    return items.isEmpty ? '全部场景不扣分' : '${items.join(' · ')} 分';
  }
}

ScoreRules scoreRulesOf(Workspace store) =>
    ScoreRules.fromSettings(store.settings['scoreRules']);

class ScoreLine {
  const ScoreLine({
    required this.label,
    required this.count,
    required this.unit,
    required this.points,
  });

  final String label;
  final int count;
  final String unit;
  final double points;

  double get deduction => count * points;
}

class PersonScore {
  PersonScore({
    required this.personId,
    required this.name,
    required this.base,
    required this.lines,
  });

  final String personId;
  final String name;
  final double base;
  final List<ScoreLine> lines;

  double get deduction =>
      lines.fold<double>(0, (total, line) => total + line.deduction);

  /// The score never drops below zero, matching how an attendance sheet floors
  /// the monthly result instead of showing a negative balance.
  double get score => math.max(0, base - deduction);

  /// True when nothing in the range actually cost points.
  bool get clean => !lines.any((line) => line.deduction > 0);

  String get summary {
    final hits = lines.where((line) => line.deduction > 0).toList();
    if (hits.isEmpty) return '无扣分';
    return hits
        .map((line) => '${line.label} ${line.count}${line.unit}')
        .join(' · ');
  }
}

/// Scores every non-deleted person who has a live record or a confirmed leave
/// inside the inclusive [from]..[to] range. People without any activity are
/// omitted so a long roster does not read as a wall of 100s.
List<PersonScore> attendanceScores(
  Workspace store,
  String from,
  String to, {
  ScoreRules? rules,
}) {
  final policy = rules ?? scoreRulesOf(store);

  final leaveDays = <String, Map<String, int>>{};
  for (final leave in store.leavesInRange(from, to)) {
    final start = leave.startDay.compareTo(from) < 0 ? from : leave.startDay;
    final end = leave.endDay.compareTo(to) > 0 ? to : leave.endDay;
    final a = DateTime.tryParse(start);
    final b = DateTime.tryParse(end);
    if (a == null || b == null) continue;
    final days = b.difference(a).inDays + 1;
    if (days <= 0) continue;
    final perType = leaveDays.putIfAbsent(leave.personId, () => {});
    perType[leave.type] = (perType[leave.type] ?? 0) + days;
  }

  final statusTimes = <String, Map<String, int>>{};
  final peopleWithEntries = <String>{};
  for (final entry in store.entries) {
    if (entry.deleted) continue;
    if (entry.day.compareTo(from) < 0 || entry.day.compareTo(to) > 0) continue;
    peopleWithEntries.add(entry.personId);
    final status = entry.fields['status'] ?? '';
    if (policy.statusPoints(status) <= 0) continue;
    final perStatus = statusTimes.putIfAbsent(entry.personId, () => {});
    perStatus[status] = (perStatus[status] ?? 0) + 1;
  }

  final activeIds = {...peopleWithEntries, ...leaveDays.keys};
  final scores = <PersonScore>[];
  for (final person in store.people) {
    if (person.deleted || !activeIds.contains(person.id)) continue;
    final lines = <ScoreLine>[];
    final counts = leaveDays[person.id] ?? const <String, int>{};
    for (final type in leaveTypes) {
      final count = counts[type] ?? 0;
      if (count == 0) continue;
      lines.add(
        ScoreLine(
          label: type,
          count: count,
          unit: '天',
          points: policy.leavePoints(type),
        ),
      );
    }
    for (final type in counts.keys) {
      if (leaveTypes.contains(type)) continue;
      lines.add(
        ScoreLine(
          label: type,
          count: counts[type]!,
          unit: '天',
          points: policy.leavePoints(type),
        ),
      );
    }
    final times = statusTimes[person.id] ?? const <String, int>{};
    for (final status in scoreStatuses) {
      final count = times[status] ?? 0;
      if (count == 0) continue;
      lines.add(
        ScoreLine(
          label: status,
          count: count,
          unit: '次',
          points: policy.statusPoints(status),
        ),
      );
    }
    scores.add(
      PersonScore(
        personId: person.id,
        name: person.name,
        base: policy.base,
        lines: lines,
      ),
    );
  }
  scores.sort((a, b) {
    final byScore = a.score.compareTo(b.score);
    return byScore != 0 ? byScore : a.name.compareTo(b.name);
  });
  return scores;
}
