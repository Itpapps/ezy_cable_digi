import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services/debug_log_service.dart';

/// In-app API debug console — lists every SOAP/REST call with timing, status,
/// and (masked) payloads. Diagnostics only; its entry point is gated behind
/// `kDebugMode`, so this screen is unreachable in release builds.
class DebugConsoleScreen extends StatefulWidget {
  const DebugConsoleScreen({super.key});

  @override
  State<DebugConsoleScreen> createState() => _DebugConsoleScreenState();
}

class _DebugConsoleScreenState extends State<DebugConsoleScreen> {
  static const Color _accent = Color(0xFF0D47A1);
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  final Set<int> _expanded = {};

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _copy(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copied'), duration: const Duration(seconds: 2)),
    );
  }

  Color _statusColor(int? status) {
    if (status == null) return Colors.grey;
    if (status >= 200 && status < 300) return Colors.green.shade600;
    if (status >= 400 && status < 500) return Colors.orange.shade700;
    if (status >= 500) return Colors.red.shade600;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    final svc = DebugLogService.instance;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        title: const Text('API Debug Console',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'text':
                  _copy(svc.exportText(), 'Log text');
                  break;
                case 'json':
                  _copy(svc.exportJson(), 'Log JSON');
                  break;
                case 'clear':
                  svc.clear();
                  break;
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'text', child: Text('Copy all (text)')),
              PopupMenuItem(value: 'json', child: Text('Export JSON')),
              PopupMenuItem(value: 'clear', child: Text('Clear logs')),
            ],
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: svc,
        builder: (context, _) {
          final all = svc.entries;
          final entries = _query.isEmpty
              ? all
              : all
                  .where((e) =>
                      e.endpoint.toLowerCase().contains(_query.toLowerCase()) ||
                      e.method.toLowerCase().contains(_query.toLowerCase()))
                  .toList();
          return Column(
            children: [
              _controls(svc, entries.length),
              const Divider(height: 1),
              Expanded(
                child: entries.isEmpty
                    ? _empty(svc.enabled)
                    : ListView.builder(
                        padding: const EdgeInsets.all(10),
                        itemCount: entries.length,
                        itemBuilder: (_, i) => _card(entries[i], i),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _controls(DebugLogService svc, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Enable API logging',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
              Switch(
                value: svc.enabled,
                activeThumbColor: _accent,
                onChanged: (v) => svc.setEnabled(v),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Filter by endpoint / method…',
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _query = '');
                      },
                    ),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text('$count entries',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              const Spacer(),
              if (!svc.enabled)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('LOGGING OFF',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade700)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _empty(bool enabled) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.terminal, size: 44, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              enabled
                  ? 'No API calls logged yet.\nMake a request to see it here.'
                  : 'Logging is off.\nEnable it above to start capturing.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(DebugLogEntry e, int index) {
    final isOpen = _expanded.contains(index);
    final ts = '${e.timestamp.hour.toString().padLeft(2, '0')}:'
        '${e.timestamp.minute.toString().padLeft(2, '0')}:'
        '${e.timestamp.second.toString().padLeft(2, '0')}';
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() =>
            isOpen ? _expanded.remove(index) : _expanded.add(index)),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(ts,
                      style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 10,
                          color: Colors.grey.shade600)),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(e.method,
                        style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: _accent)),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(e.endpoint,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ),
                  if (e.httpStatus != null || !e.ok) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: _statusColor(e.httpStatus).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(e.httpStatus?.toString() ?? 'ERR',
                          style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: _statusColor(e.httpStatus))),
                    ),
                  ],
                  const SizedBox(width: 6),
                  Text('${e.durationMs}ms',
                      style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 10,
                          color: Colors.grey.shade600)),
                  Icon(isOpen ? Icons.expand_less : Icons.expand_more,
                      size: 16, color: Colors.grey.shade500),
                ],
              ),
              if (e.error != null && !isOpen) ...[
                const SizedBox(height: 4),
                Text(e.error!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 10,
                        color: Colors.red.shade600)),
              ],
              if (isOpen) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => _copy(e.toFormattedText(), 'Entry'),
                    icon: const Icon(Icons.copy, size: 14),
                    label: const Text('Copy'),
                    style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        visualDensity: VisualDensity.compact),
                  ),
                ),
                if (e.requestData.isNotEmpty)
                  _section('REQUEST', _prettyJson(e.requestData)),
                if (e.responsePreview != null &&
                    e.responsePreview!.isNotEmpty)
                  _section('RESPONSE', e.responsePreview!),
                if (e.error != null) _section('ERROR', e.error!, err: true),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(String label, String body, {bool err = false}) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: Colors.grey.shade600)),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 200),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: err ? Colors.red.shade50 : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(6),
            ),
            child: SingleChildScrollView(
              child: SelectableText(body,
                  style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      height: 1.4,
                      color: err ? Colors.red.shade700 : Colors.black87)),
            ),
          ),
        ],
      ),
    );
  }

  String _prettyJson(Map<String, dynamic> data) {
    try {
      return const JsonEncoder.withIndent('  ').convert(data);
    } catch (_) {
      return data.toString();
    }
  }
}
