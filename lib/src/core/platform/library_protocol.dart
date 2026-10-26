import 'dart:convert';

/// Wire DTOs preserve the native protocol while validation stays out of screens.
class StateWriteRequest {
  StateWriteRequest(this.key, Map<String, dynamic>? value)
    : encodedValue = value == null ? null : jsonEncode(value) {
    if (key.isEmpty) throw ArgumentError('State key cannot be empty.');
  }
  final String key;
  final String? encodedValue;
  Map<String, Object?> toWire() => {'key': key, 'value': encodedValue};
}

Map<String, dynamic> decodeState(String value) {
  final decoded = jsonDecode(value);
  if (decoded is! Map) {
    throw const FormatException('State response must be an object.');
  }
  return Map<String, dynamic>.from(decoded);
}
