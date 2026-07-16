import 'package:http/http.dart' as http;

import '../services/debug_log_service.dart';

/// Thrown when a SOAP call does not return HTTP 200.
class SoapException implements Exception {
  final String message;
  final int? statusCode;
  final String? body;
  SoapException(this.message, {this.statusCode, this.body});

  @override
  String toString() => 'SoapException(${statusCode ?? '-'}): $message';
}

/// Minimal SOAP 1.1 transport — the Flutter equivalent of the Android app's
/// ksoap2 `HttpTransportSE`. Builds the same envelope the app sends, POSTs it
/// with the existing `http` package, and returns the raw XML response.
class SoapClient {
  SoapClient._();
  static final SoapClient instance = SoapClient._();

  /// ksoap2-android's default User-Agent. Some Digi servers sit behind a WAF
  /// that only accepts this value (others return HTTP 403), so we match it.
  static const String _userAgent = 'ksoap2-android/2.6.0+';

  /// Send a SOAP request and return the raw response body (XML).
  Future<String> call({
    required String url,
    required String namespace,
    required String soapAction,
    required String methodName,
    required String wrapper,
    required String wrapperType,
    required Map<String, Object?> fields,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final body = _buildEnvelope(
      namespace: namespace,
      methodName: methodName,
      wrapper: wrapper,
      wrapperType: wrapperType,
      fields: fields,
    );

    // ── Debug console hook (observational only) ──────────────────────────
    // Times/records the call for the in-app API console when logging is ON.
    // When OFF, `sw` is null → zero work. Any thrown error is rethrown
    // unchanged; return value and timeout behaviour are untouched.
    final dbg = DebugLogService.instance;
    final sw = dbg.enabled ? (Stopwatch()..start()) : null;
    late final http.Response res;
    try {
      res = await http
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'text/xml;charset=utf-8',
              'SOAPAction': soapAction,
              'User-Agent': _userAgent,
            },
            body: body,
          )
          .timeout(timeout);
    } catch (e) {
      if (sw != null) {
        dbg.log(DebugLogEntry(
          timestamp: DateTime.now(),
          method: 'SOAP',
          endpoint: methodName,
          requestData: DebugLogService.maskFields(fields),
          durationMs: sw.elapsedMilliseconds,
          error: e.toString(),
        ));
      }
      rethrow;
    }

    if (sw != null) {
      dbg.log(DebugLogEntry(
        timestamp: DateTime.now(),
        method: 'SOAP',
        endpoint: methodName,
        requestData: DebugLogService.maskFields(fields),
        httpStatus: res.statusCode,
        responsePreview: DebugLogService.preview(res.body),
        durationMs: sw.elapsedMilliseconds,
        ok: res.statusCode == 200,
      ));
    }

    if (res.statusCode != 200) {
      throw SoapException('HTTP ${res.statusCode}',
          statusCode: res.statusCode, body: res.body);
    }
    return res.body;
  }

  // Emits the SAME envelope ksoap2 (SoapSerializationEnvelope, VER11) sends, as
  // proven by MagikDigi production logs:
  //   <v:Envelope xmlns:i=… xmlns:d=… xmlns:c=… xmlns:v=…>
  //     <v:Header/><v:Body>
  //       <n0:methodName xmlns:n0="namespace">
  //         <wrapper i:type="n0:wrapperType"> ...bare fields... </wrapper>
  //       </n0:methodName>
  //     </v:Body></v:Envelope>
  // The wrapper carries i:type so the PHP SOAP server maps it to its struct;
  // child fields are bare (production log shows no per-field i:type).
  String _buildEnvelope({
    required String namespace,
    required String methodName,
    required String wrapper,
    required String wrapperType,
    required Map<String, Object?> fields,
  }) {
    final inner = StringBuffer();
    fields.forEach((k, v) => inner.write('<$k>${_escape('${v ?? ''}')}</$k>'));
    return '<v:Envelope '
        'xmlns:i="http://www.w3.org/2001/XMLSchema-instance" '
        'xmlns:d="http://www.w3.org/2001/XMLSchema" '
        'xmlns:c="http://schemas.xmlsoap.org/soap/encoding/" '
        'xmlns:v="http://schemas.xmlsoap.org/soap/envelope/">'
        '<v:Header/>'
        '<v:Body>'
        '<n0:$methodName xmlns:n0="$namespace">'
        '<$wrapper i:type="n0:$wrapperType">$inner</$wrapper>'
        '</n0:$methodName>'
        '</v:Body>'
        '</v:Envelope>';
  }

  static String _escape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  /// Pull a single field value out of a SOAP/XML response.
  /// e.g. readField(xml, 'authToken') → the token string.
  ///
  /// The opening tag is matched WITH OR WITHOUT XML attributes — some SOAP
  /// servers add a type attribute to typed/numeric fields (e.g.
  /// `<Amt i:type="d:double">123.0</Amt>`), which a plain `<Amt>` match would
  /// miss and return null. The attribute group is optional, so every tag that
  /// matched before still matches identically (safe superset); `<$field ...>`
  /// still cannot match a different tag like `<${field}Code>` because the char
  /// after the name must be whitespace or `>`.
  static String? readField(String xml, String field) {
    final m = RegExp('<$field(?:\\s[^>]*)?>(.*?)</$field>', dotAll: true)
        .firstMatch(xml);
    return m?.group(1)?.trim();
  }

  /// Return the inner XML of EVERY `tag` occurrence — for responses that repeat a
  /// structured element (e.g. searchCustomer's repeated searchCustomerList items).
  static List<String> readAll(String xml, String tag) {
    return RegExp('<$tag>(.*?)</$tag>', dotAll: true)
        .allMatches(xml)
        .map((m) => m.group(1) ?? '')
        .toList();
  }
}
