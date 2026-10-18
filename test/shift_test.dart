import 'package:flutter_test/flutter_test.dart';
import 'package:qingluan_attendance/core/data/shift.dart';

void main() {
  test('falls back to 09:00–18:00 with 10 minutes grace', () {
    final shift = Shift.fromSettings(const {});
    expect(shift.start, '09:00');
    expect(shift.end, '18:00');
    expect(shift.graceMinutes, 10);
    expect(shift.valid, isTrue);
  });

  test('ignores malformed settings instead of breaking the roster', () {
    final shift = Shift.fromSettings(const {
      'shiftStart': '9:5',
      'shiftEnd': '25:00',
      'shiftGrace': 'abc',
    });
    expect(shift.start, '09:00');
    expect(shift.end, '18:00');
    expect(shift.graceMinutes, 10);
  });

  test('reads a real configuration', () {
    final shift = Shift.fromSettings(const {
      'shiftStart': '08:30',
      'shiftEnd': '17:30',
      'shiftGrace': 0,
    });
    expect(shift.label, '08:30–17:30');
    expect(shift.graceMinutes, 0);
  });

  test('check-in inside the grace window is normal, later is late', () {
    final shift = Shift.fromSettings(const {});
    // business clock is UTC+8, so 01:05Z == 09:05 Beijing.
    expect(shift.statusForIn(DateTime.utc(2026, 10, 18, 1, 5)), '正常');
    // 09:10 exactly is still inside the 10 minute grace.
    expect(shift.statusForIn(DateTime.utc(2026, 10, 18, 1, 10)), '正常');
    expect(shift.statusForIn(DateTime.utc(2026, 10, 18, 1, 11)), '迟到');
    expect(Shift.clock(DateTime.utc(2026, 10, 18, 1, 11)), '09:11');
  });

  test('check-out before the shift end is early leave', () {
    final shift = Shift.fromSettings(const {});
    expect(
      shift.statusForOut(DateTime.utc(2026, 10, 18, 9, 0), inStatus: '正常'),
      '早退',
    );
    expect(
      shift.statusForOut(DateTime.utc(2026, 10, 18, 10, 30), inStatus: '正常'),
      '正常',
    );
  });

  test('a late check-in is not rewritten to early leave', () {
    final shift = Shift.fromSettings(const {});
    expect(
      shift.statusForOut(DateTime.utc(2026, 10, 18, 9, 0), inStatus: '迟到'),
      '迟到',
    );
  });
}
