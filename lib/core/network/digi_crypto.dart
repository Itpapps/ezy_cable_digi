import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Flutter port of Android `Decryptions.java` + the `ApiCallRestClient` envelope
/// used by EVERY `/digi_rest_api/...` endpoint. This is **NOT real cryptography**
/// (no keys/AES/RSA) — it's a custom hex-obfuscation. Ported 1:1 so the server
/// accepts our requests and we can read its responses.
///
/// - `hexconv(s)`   = Java `Integer.toHexString((int)c)` per char (no padding).
/// - `encryptions(d)` = rand5 + hexconv(hexconv(d)) + rand5.
/// - `decryptions(x)` = strip 5 + 5 random chars, then 3 hex-decode layers.
/// Request:  `payload = encryptions(hexconv(json))`, `hash = hexconv(json)`,
///           `env_key = encryptions(hexconv('{"app_env_key":"selfcareapps"}'))`.
/// Response: `decryptions(body.payload)` → inner JSON (`status_code`/`status_message`).
class DigiCrypto {
  DigiCrypto._();
  static final Random _rand = Random();

  /// Hex-encode each UTF-16 code unit (matches Java `Integer.toHexString`). For
  /// printable ASCII / hex-digit strings every unit is >= 0x20 → 2 hex digits.
  static String hexconv(String s) =>
      s.codeUnits.map((u) => u.toRadixString(16)).join();

  /// rand5 + hexconv(hexconv(data)) + rand5 (rand 10000..99999, like Java).
  static String encryptions(String data) {
    final two = hexconv(hexconv(data));
    final r1 = _rand.nextInt(90000) + 10000;
    final r2 = _rand.nextInt(90000) + 10000;
    return '$r1$two$r2';
  }

  /// One hex-decode layer: 2-hex pairs → bytes → UTF-8 (handles multibyte names).
  static String _layer(String h) {
    final bytes = <int>[];
    for (var i = 0; i + 1 < h.length; i += 2) {
      final b = int.tryParse(h.substring(i, i + 2), radix: 16);
      if (b != null) bytes.add(b);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// Strip the 5-char random prefix + 5-char suffix, then reverse 3 hex layers.
  static String decryptions(String decry) {
    if (decry.length <= 10) return '';
    var x = decry.substring(5, decry.length - 5);
    x = _layer(x);
    x = _layer(x);
    x = _layer(x);
    return x;
  }

  /// DIAGNOSTIC — decode ONE hex layer. The digi_rest_api response `hash` field
  /// is `hexconv(json)` (a single hex layer), so this reverses it back to JSON.
  static String hexToString(String hex) => _layer(hex);

  /// The fixed env-key envelope value sent with every request.
  static String envKey() =>
      encryptions(hexconv('{"app_env_key":"selfcareapps"}'));

  static String _b64url(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', ''); // JWT base64url, no padding

  /// The `apitoken` JWT header every `/digi_rest_api/` request needs (Android
  /// `ApiCallRestClient.getHeaders():189-206`): HS256, secret "fd4f564545",
  /// claims `method_name` (the endpoint segment) + `request_time` (unix seconds).
  static String apiToken(String methodName) {
    final ts = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final header = _b64url(utf8.encode('{"alg":"HS256","typ":"JWT"}'));
    final payload = _b64url(
        utf8.encode('{"method_name":"$methodName","request_time":"$ts"}'));
    final signingInput = '$header.$payload';
    final sig = Hmac(sha256, utf8.encode('fd4f564545'))
        .convert(utf8.encode(signingInput))
        .bytes;
    return '$signingInput.${_b64url(sig)}';
  }
}
