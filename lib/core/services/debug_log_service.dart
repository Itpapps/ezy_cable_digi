import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One captured API call, shown in the in-app debug console.
///
/// Presentation/diagnostics only — created by the transport layer
/// (`SoapClient` / `RestClient`) purely to observe timing + status. It never
/// participates in business logic.
@immutable
class DebugLogEntry {
  final DateTime timestamp;
  final String method; // 'SOAP' | 'POST'
  final String endpoint; // SOAP methodName | REST path
  final Map<String, dynamic> requestData; // secrets masked
  final int? httpStatus;
  final String? responsePreview; // truncated
  final int durationMs;
  final String? error;
  final bool ok;

  const DebugLogEntry({
    required this.timestamp,
    required this.method,
    required this.endpoint,
    this.requestData = const {},
    this.httpStatus,
    this.responsePreview,
    this.durationMs = 0,
    this.error,
    this.ok = false,
  });

  String _ts() {
    String two(int n) => n.toString().padLeft(2, '0');
    String three(int n) => n.toString().padLeft(3, '0');
    return '${two(timestamp.hour)}:${two(timestamp.minute)}:'
        '${two(timestamp.second)}.${three(timestamp.millisecond)}';
  }

  String toFormattedText() {
    final buf = StringBuffer();
    buf.writeln('[${_ts()}] $method $endpoint');
    buf.writeln('  Status: ${httpStatus ?? "N/A"}  |  Duration: ${durationMs}ms  '
        '|  ${ok ? "OK" : "FAIL"}');
    if (requestData.isNotEmpty) {
      buf.writeln('  Request: ${_pretty(requestData)}');
    }
    if (responsePreview != null && responsePreview!.isNotEmpty) {
      buf.writeln('  Response: ${responsePreview!}');
    }
    if (error != null) {
      buf.writeln('  Error: $error');
    }
    return buf.toString();
  }

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'method': method,
        'endpoint': endpoint,
        'requestData': requestData,
        'httpStatus': httpStatus,
        'responsePreview': responsePreview,
        'durationMs': durationMs,
        'error': error,
        'ok': ok,
      };

  static String _pretty(Map<String, dynamic> map) {
    try {
      return const JsonEncoder.withIndent('  ').convert(map);
    } catch (_) {
      return map.toString();
    }
  }
}

/// In-memory ring buffer + enable toggle backing the in-app debug console.
///
/// Plain singleton + [ChangeNotifier] (same pattern as `OfflineModeService` /
/// `NotificationRepository`) — no Riverpod, no new dependency. When [enabled]
/// is false, [log] returns immediately, so the transport hooks cost ~one bool
/// check. The console screen's entry point is gated behind `kDebugMode`, so it
/// is compiled out of release builds entirely.
class DebugLogService extends ChangeNotifier {
  DebugLogService._() {
    _loadEnabled();
  }
  static final DebugLogService instance = DebugLogService._();

  static const String _prefKey = 'debug_logging_enabled';
  static const int _maxEntries = 100;
  static const int _previewLimit = 4000; // ~4 KB body preview cap

  final List<DebugLogEntry> _entries = [];
  bool _enabled = false;

  bool get enabled => _enabled;
  List<DebugLogEntry> get entries => List.unmodifiable(_entries);

  Future<void> _loadEnabled() async {
    try {
      final p = await SharedPreferences.getInstance();
      _enabled = p.getBool(_prefKey) ?? false;
      if (_enabled) notifyListeners();
    } catch (_) {
      // prefs unavailable — stay disabled
    }
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_prefKey, value);
    } catch (_) {
      // best-effort persistence
    }
  }

  void log(DebugLogEntry entry) {
    if (!_enabled) return;
    _entries.insert(0, entry);
    if (_entries.length > _maxEntries) {
      _entries.removeLast();
    }
    notifyListeners();
  }

  void clear() {
    _entries.clear();
    notifyListeners();
  }

  String exportText() {
    final buf = StringBuffer()
      ..writeln('=== EzyCableDigi API Debug Log ===')
      ..writeln('Exported: ${DateTime.now().toIso8601String()}')
      ..writeln('Entries: ${_entries.length}')
      ..writeln('');
    for (final e in _entries) {
      buf
        ..writeln(e.toFormattedText())
        ..writeln('---');
    }
    return buf.toString();
  }

  String exportJson() => const JsonEncoder.withIndent('  ')
      .convert(_entries.map((e) => e.toJson()).toList());

  // ── Helpers used by the transport hooks (SoapClient / RestClient) ─────────

  static const List<String> _sensitive = [
    'token',
    'password',
    'pwd',
    'payload',
    'hash',
    'env_key',
  ];

  /// Copies [fields] to a display map, masking any value whose key looks like a
  /// secret. Never throws.
  static Map<String, dynamic> maskFields(Map<dynamic, dynamic> fields) {
    final out = <String, dynamic>{};
    try {
      fields.forEach((k, v) {
        final key = k.toString();
        final lower = key.toLowerCase();
        final secret = _sensitive.any((s) => lower.contains(s));
        out[key] = secret ? '***' : (v ?? '').toString();
      });
    } catch (_) {
      // defensive — a bad map must never break a network call
    }
    return out;
  }

  /// Truncates a response body for display so the buffer stays bounded.
  static String preview(String body) => body.length > _previewLimit
      ? '${body.substring(0, _previewLimit)}…[truncated ${body.length} chars]'
      : body;
}
