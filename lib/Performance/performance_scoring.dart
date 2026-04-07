import 'package:cloud_firestore/cloud_firestore.dart';

class DeductionReason {
  final DateTime date;
  final String reason;
  const DeductionReason(this.date, this.reason);
}

class PerformanceResult {
  final int avgWeeklyMark;
  final int avgAttendance;
  final int avgDress;
  final int avgAttitude;
  final int avgMeeting;
  final List<DeductionReason> attendanceDeductions;
  final List<DeductionReason> dressDeductions;
  final List<DeductionReason> attitudeDeductions;
  final List<DeductionReason> meetingDeductions;

  const PerformanceResult({
    required this.avgWeeklyMark,
    required this.avgAttendance,
    required this.avgDress,
    required this.avgAttitude,
    required this.avgMeeting,
    required this.attendanceDeductions,
    required this.dressDeductions,
    required this.attitudeDeductions,
    required this.meetingDeductions,
  });
}

String formatDeductionDate(DateTime date) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '${date.day} ${months[date.month - 1]}';
}

DateTime _parseDate(dynamic ts) {
  if (ts is Timestamp) return ts.toDate();
  return DateTime.parse(ts.toString());
}

PerformanceResult calculatePerformance(List<Map<String, dynamic>> forms) {
  if (forms.isEmpty) {
    return const PerformanceResult(
      avgWeeklyMark: 0,
      avgAttendance: 0,
      avgDress: 0,
      avgAttitude: 0,
      avgMeeting: 0,
      attendanceDeductions: [],
      dressDeductions: [],
      attitudeDeductions: [],
      meetingDeductions: [],
    );
  }

  // Sort forms chronologically
  final sortedForms = [...forms]..sort((a, b) =>
      _parseDate(a['timestamp']).compareTo(_parseDate(b['timestamp'])));

  // Deduplicate: keep only the latest document per date (handles duplicates in Firestore)
  final formsByDate = <String, Map<String, dynamic>>{};
  for (final form in sortedForms) {
    final date = _parseDate(form['timestamp']);
    if (date.weekday == DateTime.sunday) continue;
    final dateKey = '${date.year}-${date.month}-${date.day}';
    formsByDate[dateKey] = form; // later (chronologically) overwrites earlier
  }
  final dedupedForms = formsByDate.values.toList();

  // Pre-pass: identify which late dates should be penalized (3rd+ occurrence in the month).
  // Sundays are excluded. First 2 lates in a month are free; from the 3rd onward, deduct 5.
  int lateCount = 0;
  final penalizedLateDates = <String>{};
  for (final form in dedupedForms) {
    final formDate = _parseDate(form['timestamp']);
    if (form['attendance'] == 'late') {
      lateCount++;
      if (lateCount >= 3) {
        penalizedLateDates.add('${formDate.year}-${formDate.month}-${formDate.day}');
      }
    }
  }

  final attendanceDeductions = <DeductionReason>[];
  final dressDeductions = <DeductionReason>[];
  final attitudeDeductions = <DeductionReason>[];
  final meetingDeductions = <DeductionReason>[];

  // Group by week, excluding Sundays (already excluded in dedupedForms)
  final weekMap = <int, List<Map<String, dynamic>>>{};
  for (final form in dedupedForms) {
    final date = _parseDate(form['timestamp']);
    final week = ((date.day - 1) ~/ 7) + 1;
    weekMap.putIfAbsent(week, () => []);
    weekMap[week]!.add(form);
  }

  double totalSum = 0, attendanceSum = 0, dressSum = 0, attitudeSum = 0, meetingSum = 0;
  int weekCount = 0;

  for (final weekForms in weekMap.values) {
    int attendance = 20, dress = 20, attitude = 20, meeting = 10;

    for (final form in weekForms) {
      final date = _parseDate(form['timestamp']);
      final dateKey = '${date.year}-${date.month}-${date.day}';
      final dateOnly = DateTime(date.year, date.month, date.day);
      final att = form['attendance'];

      if (att == 'late' && penalizedLateDates.contains(dateKey)) {
        attendance -= 5;
        attendanceDeductions.add(DeductionReason(dateOnly, 'Late attendance'));
      } else if (att == 'notApproved') {
        attendance -= 10;
        attendanceDeductions.add(DeductionReason(dateOnly, 'Unapproved leave'));
      }

      if (att != 'approved' && att != 'notApproved') {
        if (form['dressCode']?['cleanUniform'] == false) {
          dress -= 5;
          dressDeductions.add(DeductionReason(dateOnly, 'Clean Uniform'));
        }
        if (form['dressCode']?['keepInside'] == false) {
          dress -= 5;
          dressDeductions.add(DeductionReason(dateOnly, 'Keep Inside'));
        }
        if (form['dressCode']?['neatHair'] == false) {
          dress -= 5;
          dressDeductions.add(DeductionReason(dateOnly, 'Neat Hair'));
        }

        if (form['attitude']?['greetSmile'] == false) {
          attitude -= 2;
          final reason = (form['attitude']?['greetSmileReason'] ?? '').toString();
          attitudeDeductions.add(DeductionReason(dateOnly,
              'Greet/Smile${reason.isNotEmpty ? ': $reason' : ''}'));
        }
        if (form['attitude']?['askNeeds'] == false) {
          attitude -= 2;
          final reason = (form['attitude']?['askNeedsReason'] ?? '').toString();
          attitudeDeductions.add(DeductionReason(dateOnly,
              'Ask Needs${reason.isNotEmpty ? ': $reason' : ''}'));
        }
        if (form['attitude']?['helpFindProduct'] == false) {
          attitude -= 2;
          final reason = (form['attitude']?['helpFindProductReason'] ?? '').toString();
          attitudeDeductions.add(DeductionReason(dateOnly,
              'Help Find Product${reason.isNotEmpty ? ': $reason' : ''}'));
        }
        if (form['attitude']?['confirmPurchase'] == false) {
          attitude -= 2;
          final reason = (form['attitude']?['confirmPurchaseReason'] ?? '').toString();
          attitudeDeductions.add(DeductionReason(dateOnly,
              'Confirm Purchase${reason.isNotEmpty ? ': $reason' : ''}'));
        }
        if (form['attitude']?['offerHelp'] == false) {
          attitude -= 2;
          final reason = (form['attitude']?['offerHelpReason'] ?? '').toString();
          attitudeDeductions.add(DeductionReason(dateOnly,
              'Offer Help${reason.isNotEmpty ? ': $reason' : ''}'));
        }

        if (form['meeting']?['attended'] == false) {
          meeting -= 1;
          meetingDeductions.add(DeductionReason(dateOnly, 'Meeting not attended'));
        }
      }
    }

    if (attendance < 0) attendance = 0;
    if (dress < 0) dress = 0;
    if (attitude < 0) attitude = 0;
    if (meeting < 0) meeting = 0;

    totalSum += attendance + dress + attitude + meeting;
    attendanceSum += attendance;
    dressSum += dress;
    attitudeSum += attitude;
    meetingSum += meeting;
    weekCount++;
  }

  return PerformanceResult(
    avgWeeklyMark: weekCount > 0 ? (totalSum / weekCount).round() : 0,
    avgAttendance: weekCount > 0 ? (attendanceSum / weekCount).round() : 0,
    avgDress: weekCount > 0 ? (dressSum / weekCount).round() : 0,
    avgAttitude: weekCount > 0 ? (attitudeSum / weekCount).round() : 0,
    avgMeeting: weekCount > 0 ? (meetingSum / weekCount).round() : 0,
    attendanceDeductions: attendanceDeductions,
    dressDeductions: dressDeductions,
    attitudeDeductions: attitudeDeductions,
    meetingDeductions: meetingDeductions,
  );
}
