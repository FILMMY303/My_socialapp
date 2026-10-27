enum OutboxOp { upsert, update, delete }

/// One local change waiting to be sent to the cloud.
class OutboxOperation {
  const OutboxOperation({
    this.key,
    required this.table,
    required this.op,
    required this.entityKey,
    this.data = const {},
    this.match = const {},
    this.onConflict,
    this.attempts = 0,
    this.lastError,
  });

  factory OutboxOperation.fromMap(int key, Map<String, Object?> map) =>
      OutboxOperation(
        key: key,
        table: map['table'] as String,
        op: OutboxOp.values.byName(map['op'] as String),
        entityKey: map['entity_key'] as String,
        data: Map<String, Object?>.from(map['data'] as Map? ?? const {}),
        match: Map<String, Object?>.from(map['match'] as Map? ?? const {}),
        onConflict: map['on_conflict'] as String?,
        attempts: map['attempts'] as int? ?? 0,
        lastError: map['last_error'] as String?,
      );

  /// Position in the outbox; operations are sent in key order.
  final int? key;

  /// Cloud table name.
  final String table;
  final OutboxOp op;

  /// Local row this operation belongs to, e.g. `posts:<id>`.
  final String entityKey;

  /// Columns to write (upsert / update).
  final Map<String, Object?> data;

  /// Column filters identifying the row (update / delete).
  final Map<String, Object?> match;

  /// Conflict target for upserts, e.g. `post_id,user_id`.
  final String? onConflict;

  final int attempts;
  final String? lastError;

  Map<String, Object?> toMap() => {
    'table': table,
    'op': op.name,
    'entity_key': entityKey,
    'data': data,
    'match': match,
    'on_conflict': onConflict,
    'attempts': attempts,
    'last_error': lastError,
    'created_at': DateTime.now().toUtc().toIso8601String(),
  };
}
