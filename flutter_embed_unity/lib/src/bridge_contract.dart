import 'dart:convert';

const int bridgeContractVersion = 1;

class BridgeEnvelope {
  const BridgeEnvelope({
    required this.v,
    required this.type,
    required this.msgId,
    required this.method,
    required this.ts,
    this.corrId,
    this.payload,
    this.err,
    this.traceId,
  });

  factory BridgeEnvelope.request({
    String? msgId,
    required String method,
    Object? payload,
    int? ts,
    String? traceId,
  }) {
    return BridgeEnvelope(
      v: bridgeContractVersion,
      type: requestType,
      msgId: msgId ?? _nextMessageId(),
      method: method,
      payload: payload,
      ts: ts ?? DateTime.now().millisecondsSinceEpoch,
      traceId: traceId,
    );
  }

  factory BridgeEnvelope.response({
    String? msgId,
    required String corrId,
    required String method,
    Object? payload,
    int? ts,
    String? traceId,
  }) {
    return BridgeEnvelope(
      v: bridgeContractVersion,
      type: responseType,
      msgId: msgId ?? _nextMessageId(),
      corrId: corrId,
      method: method,
      payload: payload,
      ts: ts ?? DateTime.now().millisecondsSinceEpoch,
      traceId: traceId,
    );
  }

  factory BridgeEnvelope.event({
    String? msgId,
    required String method,
    Object? payload,
    int? ts,
    String? traceId,
  }) {
    return BridgeEnvelope(
      v: bridgeContractVersion,
      type: eventType,
      msgId: msgId ?? _nextMessageId(),
      method: method,
      payload: payload,
      ts: ts ?? DateTime.now().millisecondsSinceEpoch,
      traceId: traceId,
    );
  }

  factory BridgeEnvelope.error({
    String? msgId,
    required String corrId,
    required String method,
    required BridgeError err,
    Object? payload,
    int? ts,
    String? traceId,
  }) {
    return BridgeEnvelope(
      v: bridgeContractVersion,
      type: errorType,
      msgId: msgId ?? _nextMessageId(),
      corrId: corrId,
      method: method,
      payload: payload,
      err: err,
      ts: ts ?? DateTime.now().millisecondsSinceEpoch,
      traceId: traceId,
    );
  }

  factory BridgeEnvelope.decodeString(String value) {
    final Object? decoded;
    try {
      decoded = jsonDecode(value);
    } on FormatException catch (error) {
      throw BridgeContractDecodeException(
        'Invalid BridgeEnvelope JSON: ${error.message}',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const BridgeContractDecodeException(
        'BridgeEnvelope JSON must be an object.',
      );
    }
    return BridgeEnvelope.decodeJson(decoded);
  }

  factory BridgeEnvelope.decodeJson(Map<String, dynamic> json) {
    final v = _required<int>(json, 'v');
    if (v != bridgeContractVersion) {
      throw BridgeContractDecodeException(
        'Unsupported BridgeEnvelope version: $v.',
      );
    }

    final type = _required<String>(json, 'type');
    if (!validTypes.contains(type)) {
      throw BridgeContractDecodeException(
        'Invalid BridgeEnvelope type: $type.',
      );
    }

    final msgId = _required<String>(json, 'msgId');
    final method = _required<String>(json, 'method');
    final ts = _required<int>(json, 'ts');
    final corrId = _optional<String>(json, 'corrId');
    final traceId = _optional<String>(json, 'traceId');

    BridgeError? err;
    if (type == errorType) {
      final errJson = _required<Map<String, dynamic>>(json, 'err');
      err = BridgeError.fromJson(errJson);
      if (corrId == null || corrId.isEmpty) {
        throw const BridgeContractDecodeException(
          'BridgeEnvelope err requires corrId.',
        );
      }
    }
    if (type == responseType && (corrId == null || corrId.isEmpty)) {
      throw const BridgeContractDecodeException(
        'BridgeEnvelope resp requires corrId.',
      );
    }

    return BridgeEnvelope(
      v: v,
      type: type,
      msgId: msgId,
      corrId: corrId,
      method: method,
      payload: json['payload'],
      err: err,
      ts: ts,
      traceId: traceId,
    );
  }

  static const requestType = 'req';
  static const responseType = 'resp';
  static const eventType = 'evt';
  static const errorType = 'err';
  static const validTypes = <String>{
    requestType,
    responseType,
    eventType,
    errorType,
  };

  final int v;
  final String type;
  final String msgId;
  final String? corrId;
  final String method;
  final Object? payload;
  final BridgeError? err;
  final int ts;
  final String? traceId;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'v': v,
      'type': type,
      'msgId': msgId,
      if (corrId != null) 'corrId': corrId,
      'method': method,
      if (payload != null) 'payload': payload,
      if (err != null) 'err': err!.toJson(),
      'ts': ts,
      if (traceId != null) 'traceId': traceId,
    };
  }

  String encodeString() => jsonEncode(toJson());

  @override
  bool operator ==(Object other) {
    return other is BridgeEnvelope &&
        jsonEncode(toJson()) == jsonEncode(other.toJson());
  }

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

class BridgeError implements Exception {
  const BridgeError(this.code, this.message, {this.details});

  factory BridgeError.fromJson(Map<String, dynamic> json) {
    final code = _required<String>(json, 'code');
    final message = _required<String>(json, 'msg');
    return BridgeError(code, message, details: json['details']);
  }

  static const timeoutCode = 'BRIDGE_TIMEOUT';

  final String code;
  final String message;
  final Object? details;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'code': code,
      'msg': message,
      if (details != null) 'details': details,
    };
  }

  @override
  String toString() => 'BridgeError($code, $message)';

  @override
  bool operator ==(Object other) {
    return other is BridgeError &&
        other.code == code &&
        other.message == message &&
        jsonEncode(other.details) == jsonEncode(details);
  }

  @override
  int get hashCode => Object.hash(code, message, jsonEncode(details));
}

class BridgeContractDecodeException implements Exception {
  const BridgeContractDecodeException(this.message);

  final String message;

  @override
  String toString() => 'BridgeContractDecodeException($message)';
}

int _messageCounter = 0;

String _nextMessageId() {
  _messageCounter += 1;
  return 'dart-${DateTime.now().microsecondsSinceEpoch}-$_messageCounter';
}

T _required<T>(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value is T) {
    return value;
  }
  throw BridgeContractDecodeException(
    'BridgeEnvelope missing or invalid "$field".',
  );
}

T? _optional<T>(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value == null) {
    return null;
  }
  if (value is T) {
    return value;
  }
  throw BridgeContractDecodeException('BridgeEnvelope invalid "$field".');
}
