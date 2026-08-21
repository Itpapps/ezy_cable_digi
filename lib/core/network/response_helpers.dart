import 'dart:convert';

dynamic decodeDynamic(dynamic raw) {
  if (raw is String) {
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }
  return raw;
}

int statusCodeOf(Map<String, dynamic> data) {
  final v = data['status_code'];
  return v is int ? v : (int.tryParse('$v') ?? 3);
}
