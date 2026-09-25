import 'package:intl/intl.dart';

final _inr = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

/// ₹32,55,000
String inr(num amount) => _inr.format(amount);

/// ₹32.6 L / ₹1.08 Cr — for chips and chart labels
String inrCompact(num amount) {
  if (amount >= 10000000) return '₹${(amount / 10000000).toStringAsFixed(2)} Cr';
  if (amount >= 100000) return '₹${(amount / 100000).toStringAsFixed(1)} L';
  return inr(amount);
}

/// +91 98765 43210
String formatPhone(String? phone) {
  if (phone == null || phone.length != 10) return phone ?? '—';
  return '+91 ${phone.substring(0, 5)} ${phone.substring(5)}';
}

/// "just now", "5 min ago", "3 h ago", "2 days ago"
String timeAgo(DateTime dt) {
  final d = DateTime.now().difference(dt);
  if (d.inSeconds < 45) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  return '${d.inDays} day${d.inDays == 1 ? '' : 's'} ago';
}

final _dateTime = DateFormat('d MMM yyyy, h:mm a');
String formatDateTime(DateTime dt) => _dateTime.format(dt.toLocal());
