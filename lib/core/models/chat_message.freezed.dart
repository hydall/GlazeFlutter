// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'chat_message.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

ChatMessage _$ChatMessageFromJson(Map<String, dynamic> json) {
  return _ChatMessage.fromJson(json);
}

/// @nodoc
mixin _$ChatMessage {
  String get id => throw _privateConstructorUsedError;
  String get role => throw _privateConstructorUsedError;
  String get content => throw _privateConstructorUsedError;
  int? get timestamp => throw _privateConstructorUsedError;
  String? get personaId => throw _privateConstructorUsedError;
  String? get personaName => throw _privateConstructorUsedError;
  String? get imagePath => throw _privateConstructorUsedError;
  List<String> get swipes => throw _privateConstructorUsedError;
  int get swipeId => throw _privateConstructorUsedError;
  String? get reasoning => throw _privateConstructorUsedError;

  /// Serializes this ChatMessage to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of ChatMessage
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ChatMessageCopyWith<ChatMessage> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ChatMessageCopyWith<$Res> {
  factory $ChatMessageCopyWith(
    ChatMessage value,
    $Res Function(ChatMessage) then,
  ) = _$ChatMessageCopyWithImpl<$Res, ChatMessage>;
  @useResult
  $Res call({
    String id,
    String role,
    String content,
    int? timestamp,
    String? personaId,
    String? personaName,
    String? imagePath,
    List<String> swipes,
    int swipeId,
    String? reasoning,
  });
}

/// @nodoc
class _$ChatMessageCopyWithImpl<$Res, $Val extends ChatMessage>
    implements $ChatMessageCopyWith<$Res> {
  _$ChatMessageCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ChatMessage
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? role = null,
    Object? content = null,
    Object? timestamp = freezed,
    Object? personaId = freezed,
    Object? personaName = freezed,
    Object? imagePath = freezed,
    Object? swipes = null,
    Object? swipeId = null,
    Object? reasoning = freezed,
  }) {
    return _then(
      _value.copyWith(
            id: null == id
                ? _value.id
                : id // ignore: cast_nullable_to_non_nullable
                      as String,
            role: null == role
                ? _value.role
                : role // ignore: cast_nullable_to_non_nullable
                      as String,
            content: null == content
                ? _value.content
                : content // ignore: cast_nullable_to_non_nullable
                      as String,
            timestamp: freezed == timestamp
                ? _value.timestamp
                : timestamp // ignore: cast_nullable_to_non_nullable
                      as int?,
            personaId: freezed == personaId
                ? _value.personaId
                : personaId // ignore: cast_nullable_to_non_nullable
                      as String?,
            personaName: freezed == personaName
                ? _value.personaName
                : personaName // ignore: cast_nullable_to_non_nullable
                      as String?,
            imagePath: freezed == imagePath
                ? _value.imagePath
                : imagePath // ignore: cast_nullable_to_non_nullable
                      as String?,
            swipes: null == swipes
                ? _value.swipes
                : swipes // ignore: cast_nullable_to_non_nullable
                      as List<String>,
            swipeId: null == swipeId
                ? _value.swipeId
                : swipeId // ignore: cast_nullable_to_non_nullable
                      as int,
            reasoning: freezed == reasoning
                ? _value.reasoning
                : reasoning // ignore: cast_nullable_to_non_nullable
                      as String?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$ChatMessageImplCopyWith<$Res>
    implements $ChatMessageCopyWith<$Res> {
  factory _$$ChatMessageImplCopyWith(
    _$ChatMessageImpl value,
    $Res Function(_$ChatMessageImpl) then,
  ) = __$$ChatMessageImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String id,
    String role,
    String content,
    int? timestamp,
    String? personaId,
    String? personaName,
    String? imagePath,
    List<String> swipes,
    int swipeId,
    String? reasoning,
  });
}

/// @nodoc
class __$$ChatMessageImplCopyWithImpl<$Res>
    extends _$ChatMessageCopyWithImpl<$Res, _$ChatMessageImpl>
    implements _$$ChatMessageImplCopyWith<$Res> {
  __$$ChatMessageImplCopyWithImpl(
    _$ChatMessageImpl _value,
    $Res Function(_$ChatMessageImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of ChatMessage
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? role = null,
    Object? content = null,
    Object? timestamp = freezed,
    Object? personaId = freezed,
    Object? personaName = freezed,
    Object? imagePath = freezed,
    Object? swipes = null,
    Object? swipeId = null,
    Object? reasoning = freezed,
  }) {
    return _then(
      _$ChatMessageImpl(
        id: null == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String,
        role: null == role
            ? _value.role
            : role // ignore: cast_nullable_to_non_nullable
                  as String,
        content: null == content
            ? _value.content
            : content // ignore: cast_nullable_to_non_nullable
                  as String,
        timestamp: freezed == timestamp
            ? _value.timestamp
            : timestamp // ignore: cast_nullable_to_non_nullable
                  as int?,
        personaId: freezed == personaId
            ? _value.personaId
            : personaId // ignore: cast_nullable_to_non_nullable
                  as String?,
        personaName: freezed == personaName
            ? _value.personaName
            : personaName // ignore: cast_nullable_to_non_nullable
                  as String?,
        imagePath: freezed == imagePath
            ? _value.imagePath
            : imagePath // ignore: cast_nullable_to_non_nullable
                  as String?,
        swipes: null == swipes
            ? _value._swipes
            : swipes // ignore: cast_nullable_to_non_nullable
                  as List<String>,
        swipeId: null == swipeId
            ? _value.swipeId
            : swipeId // ignore: cast_nullable_to_non_nullable
                  as int,
        reasoning: freezed == reasoning
            ? _value.reasoning
            : reasoning // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$ChatMessageImpl implements _ChatMessage {
  const _$ChatMessageImpl({
    required this.id,
    required this.role,
    required this.content,
    this.timestamp,
    this.personaId,
    this.personaName,
    this.imagePath,
    final List<String> swipes = const [],
    this.swipeId = 0,
    this.reasoning,
  }) : _swipes = swipes;

  factory _$ChatMessageImpl.fromJson(Map<String, dynamic> json) =>
      _$$ChatMessageImplFromJson(json);

  @override
  final String id;
  @override
  final String role;
  @override
  final String content;
  @override
  final int? timestamp;
  @override
  final String? personaId;
  @override
  final String? personaName;
  @override
  final String? imagePath;
  final List<String> _swipes;
  @override
  @JsonKey()
  List<String> get swipes {
    if (_swipes is EqualUnmodifiableListView) return _swipes;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_swipes);
  }

  @override
  @JsonKey()
  final int swipeId;
  @override
  final String? reasoning;

  @override
  String toString() {
    return 'ChatMessage(id: $id, role: $role, content: $content, timestamp: $timestamp, personaId: $personaId, personaName: $personaName, imagePath: $imagePath, swipes: $swipes, swipeId: $swipeId, reasoning: $reasoning)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ChatMessageImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.role, role) || other.role == role) &&
            (identical(other.content, content) || other.content == content) &&
            (identical(other.timestamp, timestamp) ||
                other.timestamp == timestamp) &&
            (identical(other.personaId, personaId) ||
                other.personaId == personaId) &&
            (identical(other.personaName, personaName) ||
                other.personaName == personaName) &&
            (identical(other.imagePath, imagePath) ||
                other.imagePath == imagePath) &&
            const DeepCollectionEquality().equals(other._swipes, _swipes) &&
            (identical(other.swipeId, swipeId) || other.swipeId == swipeId) &&
            (identical(other.reasoning, reasoning) ||
                other.reasoning == reasoning));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
    runtimeType,
    id,
    role,
    content,
    timestamp,
    personaId,
    personaName,
    imagePath,
    const DeepCollectionEquality().hash(_swipes),
    swipeId,
    reasoning,
  );

  /// Create a copy of ChatMessage
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ChatMessageImplCopyWith<_$ChatMessageImpl> get copyWith =>
      __$$ChatMessageImplCopyWithImpl<_$ChatMessageImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ChatMessageImplToJson(this);
  }
}

abstract class _ChatMessage implements ChatMessage {
  const factory _ChatMessage({
    required final String id,
    required final String role,
    required final String content,
    final int? timestamp,
    final String? personaId,
    final String? personaName,
    final String? imagePath,
    final List<String> swipes,
    final int swipeId,
    final String? reasoning,
  }) = _$ChatMessageImpl;

  factory _ChatMessage.fromJson(Map<String, dynamic> json) =
      _$ChatMessageImpl.fromJson;

  @override
  String get id;
  @override
  String get role;
  @override
  String get content;
  @override
  int? get timestamp;
  @override
  String? get personaId;
  @override
  String? get personaName;
  @override
  String? get imagePath;
  @override
  List<String> get swipes;
  @override
  int get swipeId;
  @override
  String? get reasoning;

  /// Create a copy of ChatMessage
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ChatMessageImplCopyWith<_$ChatMessageImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

ChatSession _$ChatSessionFromJson(Map<String, dynamic> json) {
  return _ChatSession.fromJson(json);
}

/// @nodoc
mixin _$ChatSession {
  String get id => throw _privateConstructorUsedError;
  String get characterId => throw _privateConstructorUsedError;
  int get sessionIndex => throw _privateConstructorUsedError;
  List<ChatMessage> get messages => throw _privateConstructorUsedError;
  int get updatedAt => throw _privateConstructorUsedError;

  /// Serializes this ChatSession to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of ChatSession
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ChatSessionCopyWith<ChatSession> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ChatSessionCopyWith<$Res> {
  factory $ChatSessionCopyWith(
    ChatSession value,
    $Res Function(ChatSession) then,
  ) = _$ChatSessionCopyWithImpl<$Res, ChatSession>;
  @useResult
  $Res call({
    String id,
    String characterId,
    int sessionIndex,
    List<ChatMessage> messages,
    int updatedAt,
  });
}

/// @nodoc
class _$ChatSessionCopyWithImpl<$Res, $Val extends ChatSession>
    implements $ChatSessionCopyWith<$Res> {
  _$ChatSessionCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ChatSession
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? characterId = null,
    Object? sessionIndex = null,
    Object? messages = null,
    Object? updatedAt = null,
  }) {
    return _then(
      _value.copyWith(
            id: null == id
                ? _value.id
                : id // ignore: cast_nullable_to_non_nullable
                      as String,
            characterId: null == characterId
                ? _value.characterId
                : characterId // ignore: cast_nullable_to_non_nullable
                      as String,
            sessionIndex: null == sessionIndex
                ? _value.sessionIndex
                : sessionIndex // ignore: cast_nullable_to_non_nullable
                      as int,
            messages: null == messages
                ? _value.messages
                : messages // ignore: cast_nullable_to_non_nullable
                      as List<ChatMessage>,
            updatedAt: null == updatedAt
                ? _value.updatedAt
                : updatedAt // ignore: cast_nullable_to_non_nullable
                      as int,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$ChatSessionImplCopyWith<$Res>
    implements $ChatSessionCopyWith<$Res> {
  factory _$$ChatSessionImplCopyWith(
    _$ChatSessionImpl value,
    $Res Function(_$ChatSessionImpl) then,
  ) = __$$ChatSessionImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String id,
    String characterId,
    int sessionIndex,
    List<ChatMessage> messages,
    int updatedAt,
  });
}

/// @nodoc
class __$$ChatSessionImplCopyWithImpl<$Res>
    extends _$ChatSessionCopyWithImpl<$Res, _$ChatSessionImpl>
    implements _$$ChatSessionImplCopyWith<$Res> {
  __$$ChatSessionImplCopyWithImpl(
    _$ChatSessionImpl _value,
    $Res Function(_$ChatSessionImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of ChatSession
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? characterId = null,
    Object? sessionIndex = null,
    Object? messages = null,
    Object? updatedAt = null,
  }) {
    return _then(
      _$ChatSessionImpl(
        id: null == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String,
        characterId: null == characterId
            ? _value.characterId
            : characterId // ignore: cast_nullable_to_non_nullable
                  as String,
        sessionIndex: null == sessionIndex
            ? _value.sessionIndex
            : sessionIndex // ignore: cast_nullable_to_non_nullable
                  as int,
        messages: null == messages
            ? _value._messages
            : messages // ignore: cast_nullable_to_non_nullable
                  as List<ChatMessage>,
        updatedAt: null == updatedAt
            ? _value.updatedAt
            : updatedAt // ignore: cast_nullable_to_non_nullable
                  as int,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$ChatSessionImpl implements _ChatSession {
  const _$ChatSessionImpl({
    required this.id,
    required this.characterId,
    required this.sessionIndex,
    final List<ChatMessage> messages = const [],
    this.updatedAt = 0,
  }) : _messages = messages;

  factory _$ChatSessionImpl.fromJson(Map<String, dynamic> json) =>
      _$$ChatSessionImplFromJson(json);

  @override
  final String id;
  @override
  final String characterId;
  @override
  final int sessionIndex;
  final List<ChatMessage> _messages;
  @override
  @JsonKey()
  List<ChatMessage> get messages {
    if (_messages is EqualUnmodifiableListView) return _messages;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_messages);
  }

  @override
  @JsonKey()
  final int updatedAt;

  @override
  String toString() {
    return 'ChatSession(id: $id, characterId: $characterId, sessionIndex: $sessionIndex, messages: $messages, updatedAt: $updatedAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ChatSessionImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.characterId, characterId) ||
                other.characterId == characterId) &&
            (identical(other.sessionIndex, sessionIndex) ||
                other.sessionIndex == sessionIndex) &&
            const DeepCollectionEquality().equals(other._messages, _messages) &&
            (identical(other.updatedAt, updatedAt) ||
                other.updatedAt == updatedAt));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
    runtimeType,
    id,
    characterId,
    sessionIndex,
    const DeepCollectionEquality().hash(_messages),
    updatedAt,
  );

  /// Create a copy of ChatSession
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ChatSessionImplCopyWith<_$ChatSessionImpl> get copyWith =>
      __$$ChatSessionImplCopyWithImpl<_$ChatSessionImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ChatSessionImplToJson(this);
  }
}

abstract class _ChatSession implements ChatSession {
  const factory _ChatSession({
    required final String id,
    required final String characterId,
    required final int sessionIndex,
    final List<ChatMessage> messages,
    final int updatedAt,
  }) = _$ChatSessionImpl;

  factory _ChatSession.fromJson(Map<String, dynamic> json) =
      _$ChatSessionImpl.fromJson;

  @override
  String get id;
  @override
  String get characterId;
  @override
  int get sessionIndex;
  @override
  List<ChatMessage> get messages;
  @override
  int get updatedAt;

  /// Create a copy of ChatSession
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ChatSessionImplCopyWith<_$ChatSessionImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
