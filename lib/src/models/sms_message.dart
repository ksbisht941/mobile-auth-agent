class SmsMessage {
  const SmsMessage({
    required this.id,
    required this.sender,
    required this.body,
    required this.receivedAt,
    required this.type,
  });

  final String id;
  final String sender;
  final String body;
  final DateTime receivedAt;
  final int type;

  factory SmsMessage.fromMap(Map<Object?, Object?> map) {
    return SmsMessage(
      id: map['id']?.toString() ?? '',
      sender: map['address']?.toString() ?? 'Unknown',
      body: map['body']?.toString() ?? '',
      receivedAt: DateTime.fromMillisecondsSinceEpoch(_parseInt(map['date'])),
      type: _parseInt(map['type']),
    );
  }

  static int _parseInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String get typeLabel {
    switch (type) {
      case 1:
        return 'Inbox';
      case 2:
        return 'Sent';
      case 3:
        return 'Draft';
      case 4:
        return 'Outbox';
      case 5:
        return 'Failed';
      case 6:
        return 'Queued';
      default:
        return 'Type $type';
    }
  }
}