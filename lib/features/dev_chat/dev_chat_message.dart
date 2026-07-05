/// A single message in the developer chat.
///
/// Plain immutable class (no freezed) to keep this small, self-contained
/// feature free of codegen. Persisted as JSON in SharedPreferences.
enum DevMsgStatus { sending, sent, failed }

class DevChatMessage {
  const DevChatMessage({
    required this.id,
    required this.fromDev,
    required this.text,
    required this.ts,
    this.devId,
    this.devName,
    this.status = DevMsgStatus.sent,
  });

  /// Unique id. For user messages a generated id; for dev messages the KV ts.
  final String id;

  /// True when authored by a developer (left side), false for the user (right).
  final bool fromDev;

  final String text;

  /// Epoch milliseconds.
  final int ts;

  /// Telegram user id of the replying developer (dev messages only).
  final String? devId;

  /// Display name of the replying developer (dev messages only).
  final String? devName;

  /// Delivery status for user-authored messages.
  final DevMsgStatus status;

  DevChatMessage copyWith({DevMsgStatus? status}) => DevChatMessage(
        id: id,
        fromDev: fromDev,
        text: text,
        ts: ts,
        devId: devId,
        devName: devName,
        status: status ?? this.status,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'fromDev': fromDev,
        'text': text,
        'ts': ts,
        if (devId != null) 'devId': devId,
        if (devName != null) 'devName': devName,
        'status': status.name,
      };

  factory DevChatMessage.fromJson(Map<String, dynamic> j) => DevChatMessage(
        // Dev replies from /poll carry no id — synthesize a stable one from
        // (ts, devId) so repeated polls dedupe to the same message.
        id: (j['id'] as String?) ??
            'dev:${(j['ts'] as num?)?.toInt() ?? 0}:${j['devId'] ?? ''}',
        fromDev: j['fromDev'] as bool? ?? false,
        text: j['text'] as String? ?? '',
        ts: (j['ts'] as num?)?.toInt() ?? 0,
        devId: j['devId'] as String?,
        devName: j['devName'] as String?,
        status: DevMsgStatus.values.firstWhere(
          (s) => s.name == j['status'],
          orElse: () => DevMsgStatus.sent,
        ),
      );
}
