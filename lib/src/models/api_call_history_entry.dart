class ApiCallHistoryEntry {
  const ApiCallHistoryEntry({
    required this.otpCode,
    required this.sender,
    required this.smsReceivedAt,
    required this.apiCalledAt,
    required this.isSuccess,
    this.statusCode,
    this.errorMessage,
  });

  factory ApiCallHistoryEntry.fromMap(Map<Object?, Object?> map) {
    return ApiCallHistoryEntry(
      otpCode: map['otpCode']?.toString() ?? '',
      sender: map['sender']?.toString() ?? 'Unknown',
      smsReceivedAt: DateTime.fromMillisecondsSinceEpoch(_parseInt(map['smsReceivedAtMillis'])),
      apiCalledAt: DateTime.fromMillisecondsSinceEpoch(_parseInt(map['apiCalledAtMillis'])),
      isSuccess: map['isSuccess'] == true,
      statusCode: _parseNullableInt(map['statusCode']),
      errorMessage: map['errorMessage']?.toString(),
    );
  }

  final String otpCode;
  final String sender;
  final DateTime smsReceivedAt;
  final DateTime apiCalledAt;
  final bool isSuccess;
  final int? statusCode;
  final String? errorMessage;

  static int _parseInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int? _parseNullableInt(Object? value) {
    if (value == null) {
      return null;
    }

    final parsed = _parseInt(value);
    return parsed == 0 && value.toString() != '0' ? null : parsed;
  }
}