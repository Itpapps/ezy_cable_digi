import 'dart:convert';

import 'package:http/http.dart' as http;

import 'digi_crypto.dart';

/// Thrown when a REST call does not return HTTP 200 or returns a non-JSON body.
class RestException implements Exception {
  final String message;
  final int? statusCode;
  RestException(this.message, {this.statusCode});

  @override
  String toString() => 'RestException(${statusCode ?? '-'}): $message';
}

/// Minimal REST transport — the Flutter equivalent of the Android app's Volley
/// form POST. Sends `application/x-www-form-urlencoded` params and decodes the
/// JSON response. Used for the `/packagelist/...` and `/digi_rest_api/...` calls.
class RestClient {
  RestClient._();
  static final RestClient instance = RestClient._();

  /// Same User-Agent as the SOAP client — some Digi servers gate on it (403).
  static const String _userAgent = 'ksoap2-android/2.6.0+';

  /// POST [params] as form-encoded; return the decoded JSON object.
  Future<Map<String, dynamic>> postForm(
    String url,
    Map<String, String> params, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final res = await http
        .post(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'User-Agent': _userAgent,
          },
          body: params,
        )
        .timeout(timeout);

    if (res.statusCode != 200) {
      throw RestException('HTTP ${res.statusCode}', statusCode: res.statusCode);
    }
    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) {
      throw RestException('Unexpected response shape (not a JSON object)');
    }
    return decoded;
  }

  /// POST [params] as form-encoded; return the **raw string** body.
  /// Used for offline download (`/GetRequest`) and sync (`/GetCollectionData`)
  /// which return plain-text responses (not JSON).
  Future<String> postRaw(
    String url,
    Map<String, String> params, {
    Duration timeout = const Duration(seconds: 200),
  }) async {
    final res = await http
        .post(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'Accept': 'application/json',
            'User-Agent': _userAgent,
          },
          body: params,
        )
        .timeout(timeout);

    if (res.statusCode != 200) {
      throw RestException('HTTP ${res.statusCode}', statusCode: res.statusCode);
    }
    return res.body;
  }

  /// Encrypted JSON POST for `/digi_rest_api/...` (Android `ApiCallRestClient`
  /// envelope, hex-obfuscation via [DigiCrypto]). Sends `{payload, env_key, hash}`,
  /// decrypts the response `payload`, and returns the inner JSON. Mirrors Android:
  /// `status_code == 1` → `{Error_code, Error_Message}`.
  Future<Map<String, dynamic>> postEncrypted(
    String url,
    Map<String, String> params, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final paramsJson = jsonEncode(params);
    final hash = DigiCrypto.hexconv(paramsJson);
    final body = jsonEncode({
      'payload': DigiCrypto.encryptions(hash),
      'env_key': DigiCrypto.envKey(),
      'hash': hash,
    });
    // `method_name` claim = the endpoint segment after /digi_rest_api/.
    final methodName =
        url.contains('/digi_rest_api/') ? url.split('/digi_rest_api/').last : '';
    final res = await http
        .post(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/json',
            'User-Agent': _userAgent,
            'apitoken': DigiCrypto.apiToken(methodName),
          },
          body: body,
        )
        .timeout(timeout);

    if (res.statusCode != 200) {
      throw RestException('HTTP ${res.statusCode}', statusCode: res.statusCode);
    }
    final outer = jsonDecode(res.body);
    if (outer is! Map || outer['payload'] == null) {
      throw RestException('Unexpected encrypted response (no payload)');
    }
    final inner = jsonDecode(DigiCrypto.decryptions(outer['payload'].toString()));
    if (inner is! Map) {
      throw RestException('Unexpected decrypted response shape');
    }
    final map = Map<String, dynamic>.from(inner);
    if ('${map['status_code']}' == '1') {
      return {
        'Error_code': 1,
        'Error_Message': map['status_message'] ?? 'Failed',
      };
    }
    return map;
  }
}
