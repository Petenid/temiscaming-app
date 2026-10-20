import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

/// Dates and times in the user's language, Canadian style (DESIGN §5):
/// "19 oct. 2026" / "Oct 19, 2026", "13 h 58" / "1:58 p.m.".
String _localeOf(BuildContext context) =>
    '${Localizations.localeOf(context).languageCode}_CA';

String formatDate(BuildContext context, DateTime when) =>
    DateFormat.yMMMd(_localeOf(context)).format(when.toLocal());

String formatTime(BuildContext context, DateTime when) =>
    DateFormat.jm(_localeOf(context)).format(when.toLocal());

/// Just the time if it's today, otherwise the date and time.
String formatWhen(BuildContext context, DateTime when, {DateTime? now}) {
  final local = when.toLocal();
  final today = (now ?? DateTime.now()).toLocal();
  final sameDay = local.year == today.year &&
      local.month == today.month &&
      local.day == today.day;
  return sameDay
      ? formatTime(context, local)
      : '${formatDate(context, local)} ${formatTime(context, local)}';
}

/// Pickup days (dates, no time), in the user's language:
/// "mardi" / "Tuesday".
String formatWeekday(BuildContext context, DateTime day) =>
    DateFormat.EEEE(_localeOf(context)).format(day);

/// "mar. 27 oct." / "Tue, Oct 27".
String formatShortDay(BuildContext context, DateTime day) =>
    DateFormat.MMMEd(_localeOf(context)).format(day);

/// "mardi 27 octobre" / "Tuesday, October 27".
String formatLongDay(BuildContext context, DateTime day) =>
    DateFormat.MMMMEEEEd(_localeOf(context)).format(day);
