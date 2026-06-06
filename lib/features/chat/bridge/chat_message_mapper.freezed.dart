// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'chat_message_mapper.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

/// @nodoc
mixin _$ChatMessageMapperContext {
  String? get currentCharName => throw _privateConstructorUsedError;
  String? get currentCharColor => throw _privateConstructorUsedError;
  String? get currentPersonaName => throw _privateConstructorUsedError;
  String? get charAvatarDataUrl => throw _privateConstructorUsedError;
  String? get personaAvatarDataUrl => throw _privateConstructorUsedError;
  bool get isGenerating => throw _privateConstructorUsedError;
  Set<String> get coveredMemoryIds => throw _privateConstructorUsedError;
  Set<String> get pendingMemoryIds => throw _privateConstructorUsedError;
  Set<String> get draftMemoryIds => throw _privateConstructorUsedError;
  int get greetingTotal => throw _privateConstructorUsedError;

  /// messageId → aggregated block status ('running'|'done'|'error')
  Map<String, String> get blockStatusByMessageId =>
      throw _privateConstructorUsedError;

  /// Create a copy of ChatMessageMapperContext
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ChatMessageMapperContextCopyWith<ChatMessageMapperContext> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ChatMessageMapperContextCopyWith<$Res> {
  factory $ChatMessageMapperContextCopyWith(
    ChatMessageMapperContext value,
    $Res Function(ChatMessageMapperContext) then,
  ) = _$ChatMessageMapperContextCopyWithImpl<$Res, ChatMessageMapperContext>;
  @useResult
  $Res call({
    String? currentCharName,
    String? currentCharColor,
    String? currentPersonaName,
    String? charAvatarDataUrl,
    String? personaAvatarDataUrl,
    bool isGenerating,
    Set<String> coveredMemoryIds,
    Set<String> pendingMemoryIds,
    Set<String> draftMemoryIds,
    int greetingTotal,
    Map<String, String> blockStatusByMessageId,
  });
}

/// @nodoc
class _$ChatMessageMapperContextCopyWithImpl<
  $Res,
  $Val extends ChatMessageMapperContext
>
    implements $ChatMessageMapperContextCopyWith<$Res> {
  _$ChatMessageMapperContextCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ChatMessageMapperContext
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? currentCharName = freezed,
    Object? currentCharColor = freezed,
    Object? currentPersonaName = freezed,
    Object? charAvatarDataUrl = freezed,
    Object? personaAvatarDataUrl = freezed,
    Object? isGenerating = null,
    Object? coveredMemoryIds = null,
    Object? pendingMemoryIds = null,
    Object? draftMemoryIds = null,
    Object? greetingTotal = null,
    Object? blockStatusByMessageId = null,
  }) {
    return _then(
      _value.copyWith(
            currentCharName: freezed == currentCharName
                ? _value.currentCharName
                : currentCharName // ignore: cast_nullable_to_non_nullable
                      as String?,
            currentCharColor: freezed == currentCharColor
                ? _value.currentCharColor
                : currentCharColor // ignore: cast_nullable_to_non_nullable
                      as String?,
            currentPersonaName: freezed == currentPersonaName
                ? _value.currentPersonaName
                : currentPersonaName // ignore: cast_nullable_to_non_nullable
                      as String?,
            charAvatarDataUrl: freezed == charAvatarDataUrl
                ? _value.charAvatarDataUrl
                : charAvatarDataUrl // ignore: cast_nullable_to_non_nullable
                      as String?,
            personaAvatarDataUrl: freezed == personaAvatarDataUrl
                ? _value.personaAvatarDataUrl
                : personaAvatarDataUrl // ignore: cast_nullable_to_non_nullable
                      as String?,
            isGenerating: null == isGenerating
                ? _value.isGenerating
                : isGenerating // ignore: cast_nullable_to_non_nullable
                      as bool,
            coveredMemoryIds: null == coveredMemoryIds
                ? _value.coveredMemoryIds
                : coveredMemoryIds // ignore: cast_nullable_to_non_nullable
                      as Set<String>,
            pendingMemoryIds: null == pendingMemoryIds
                ? _value.pendingMemoryIds
                : pendingMemoryIds // ignore: cast_nullable_to_non_nullable
                      as Set<String>,
            draftMemoryIds: null == draftMemoryIds
                ? _value.draftMemoryIds
                : draftMemoryIds // ignore: cast_nullable_to_non_nullable
                      as Set<String>,
            greetingTotal: null == greetingTotal
                ? _value.greetingTotal
                : greetingTotal // ignore: cast_nullable_to_non_nullable
                      as int,
            blockStatusByMessageId: null == blockStatusByMessageId
                ? _value.blockStatusByMessageId
                : blockStatusByMessageId // ignore: cast_nullable_to_non_nullable
                      as Map<String, String>,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$ChatMessageMapperContextImplCopyWith<$Res>
    implements $ChatMessageMapperContextCopyWith<$Res> {
  factory _$$ChatMessageMapperContextImplCopyWith(
    _$ChatMessageMapperContextImpl value,
    $Res Function(_$ChatMessageMapperContextImpl) then,
  ) = __$$ChatMessageMapperContextImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String? currentCharName,
    String? currentCharColor,
    String? currentPersonaName,
    String? charAvatarDataUrl,
    String? personaAvatarDataUrl,
    bool isGenerating,
    Set<String> coveredMemoryIds,
    Set<String> pendingMemoryIds,
    Set<String> draftMemoryIds,
    int greetingTotal,
    Map<String, String> blockStatusByMessageId,
  });
}

/// @nodoc
class __$$ChatMessageMapperContextImplCopyWithImpl<$Res>
    extends
        _$ChatMessageMapperContextCopyWithImpl<
          $Res,
          _$ChatMessageMapperContextImpl
        >
    implements _$$ChatMessageMapperContextImplCopyWith<$Res> {
  __$$ChatMessageMapperContextImplCopyWithImpl(
    _$ChatMessageMapperContextImpl _value,
    $Res Function(_$ChatMessageMapperContextImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of ChatMessageMapperContext
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? currentCharName = freezed,
    Object? currentCharColor = freezed,
    Object? currentPersonaName = freezed,
    Object? charAvatarDataUrl = freezed,
    Object? personaAvatarDataUrl = freezed,
    Object? isGenerating = null,
    Object? coveredMemoryIds = null,
    Object? pendingMemoryIds = null,
    Object? draftMemoryIds = null,
    Object? greetingTotal = null,
    Object? blockStatusByMessageId = null,
  }) {
    return _then(
      _$ChatMessageMapperContextImpl(
        currentCharName: freezed == currentCharName
            ? _value.currentCharName
            : currentCharName // ignore: cast_nullable_to_non_nullable
                  as String?,
        currentCharColor: freezed == currentCharColor
            ? _value.currentCharColor
            : currentCharColor // ignore: cast_nullable_to_non_nullable
                  as String?,
        currentPersonaName: freezed == currentPersonaName
            ? _value.currentPersonaName
            : currentPersonaName // ignore: cast_nullable_to_non_nullable
                  as String?,
        charAvatarDataUrl: freezed == charAvatarDataUrl
            ? _value.charAvatarDataUrl
            : charAvatarDataUrl // ignore: cast_nullable_to_non_nullable
                  as String?,
        personaAvatarDataUrl: freezed == personaAvatarDataUrl
            ? _value.personaAvatarDataUrl
            : personaAvatarDataUrl // ignore: cast_nullable_to_non_nullable
                  as String?,
        isGenerating: null == isGenerating
            ? _value.isGenerating
            : isGenerating // ignore: cast_nullable_to_non_nullable
                  as bool,
        coveredMemoryIds: null == coveredMemoryIds
            ? _value._coveredMemoryIds
            : coveredMemoryIds // ignore: cast_nullable_to_non_nullable
                  as Set<String>,
        pendingMemoryIds: null == pendingMemoryIds
            ? _value._pendingMemoryIds
            : pendingMemoryIds // ignore: cast_nullable_to_non_nullable
                  as Set<String>,
        draftMemoryIds: null == draftMemoryIds
            ? _value._draftMemoryIds
            : draftMemoryIds // ignore: cast_nullable_to_non_nullable
                  as Set<String>,
        greetingTotal: null == greetingTotal
            ? _value.greetingTotal
            : greetingTotal // ignore: cast_nullable_to_non_nullable
                  as int,
        blockStatusByMessageId: null == blockStatusByMessageId
            ? _value._blockStatusByMessageId
            : blockStatusByMessageId // ignore: cast_nullable_to_non_nullable
                  as Map<String, String>,
      ),
    );
  }
}

/// @nodoc

class _$ChatMessageMapperContextImpl implements _ChatMessageMapperContext {
  const _$ChatMessageMapperContextImpl({
    this.currentCharName,
    this.currentCharColor,
    this.currentPersonaName,
    this.charAvatarDataUrl,
    this.personaAvatarDataUrl,
    required this.isGenerating,
    final Set<String> coveredMemoryIds = const {},
    final Set<String> pendingMemoryIds = const {},
    final Set<String> draftMemoryIds = const {},
    this.greetingTotal = 0,
    final Map<String, String> blockStatusByMessageId = const {},
  }) : _coveredMemoryIds = coveredMemoryIds,
       _pendingMemoryIds = pendingMemoryIds,
       _draftMemoryIds = draftMemoryIds,
       _blockStatusByMessageId = blockStatusByMessageId;

  @override
  final String? currentCharName;
  @override
  final String? currentCharColor;
  @override
  final String? currentPersonaName;
  @override
  final String? charAvatarDataUrl;
  @override
  final String? personaAvatarDataUrl;
  @override
  final bool isGenerating;
  final Set<String> _coveredMemoryIds;
  @override
  @JsonKey()
  Set<String> get coveredMemoryIds {
    if (_coveredMemoryIds is EqualUnmodifiableSetView) return _coveredMemoryIds;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableSetView(_coveredMemoryIds);
  }

  final Set<String> _pendingMemoryIds;
  @override
  @JsonKey()
  Set<String> get pendingMemoryIds {
    if (_pendingMemoryIds is EqualUnmodifiableSetView) return _pendingMemoryIds;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableSetView(_pendingMemoryIds);
  }

  final Set<String> _draftMemoryIds;
  @override
  @JsonKey()
  Set<String> get draftMemoryIds {
    if (_draftMemoryIds is EqualUnmodifiableSetView) return _draftMemoryIds;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableSetView(_draftMemoryIds);
  }

  @override
  @JsonKey()
  final int greetingTotal;

  /// messageId → aggregated block status ('running'|'done'|'error')
  final Map<String, String> _blockStatusByMessageId;

  /// messageId → aggregated block status ('running'|'done'|'error')
  @override
  @JsonKey()
  Map<String, String> get blockStatusByMessageId {
    if (_blockStatusByMessageId is EqualUnmodifiableMapView)
      return _blockStatusByMessageId;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_blockStatusByMessageId);
  }

  @override
  String toString() {
    return 'ChatMessageMapperContext(currentCharName: $currentCharName, currentCharColor: $currentCharColor, currentPersonaName: $currentPersonaName, charAvatarDataUrl: $charAvatarDataUrl, personaAvatarDataUrl: $personaAvatarDataUrl, isGenerating: $isGenerating, coveredMemoryIds: $coveredMemoryIds, pendingMemoryIds: $pendingMemoryIds, draftMemoryIds: $draftMemoryIds, greetingTotal: $greetingTotal, blockStatusByMessageId: $blockStatusByMessageId)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ChatMessageMapperContextImpl &&
            (identical(other.currentCharName, currentCharName) ||
                other.currentCharName == currentCharName) &&
            (identical(other.currentCharColor, currentCharColor) ||
                other.currentCharColor == currentCharColor) &&
            (identical(other.currentPersonaName, currentPersonaName) ||
                other.currentPersonaName == currentPersonaName) &&
            (identical(other.charAvatarDataUrl, charAvatarDataUrl) ||
                other.charAvatarDataUrl == charAvatarDataUrl) &&
            (identical(other.personaAvatarDataUrl, personaAvatarDataUrl) ||
                other.personaAvatarDataUrl == personaAvatarDataUrl) &&
            (identical(other.isGenerating, isGenerating) ||
                other.isGenerating == isGenerating) &&
            const DeepCollectionEquality().equals(
              other._coveredMemoryIds,
              _coveredMemoryIds,
            ) &&
            const DeepCollectionEquality().equals(
              other._pendingMemoryIds,
              _pendingMemoryIds,
            ) &&
            const DeepCollectionEquality().equals(
              other._draftMemoryIds,
              _draftMemoryIds,
            ) &&
            (identical(other.greetingTotal, greetingTotal) ||
                other.greetingTotal == greetingTotal) &&
            const DeepCollectionEquality().equals(
              other._blockStatusByMessageId,
              _blockStatusByMessageId,
            ));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    currentCharName,
    currentCharColor,
    currentPersonaName,
    charAvatarDataUrl,
    personaAvatarDataUrl,
    isGenerating,
    const DeepCollectionEquality().hash(_coveredMemoryIds),
    const DeepCollectionEquality().hash(_pendingMemoryIds),
    const DeepCollectionEquality().hash(_draftMemoryIds),
    greetingTotal,
    const DeepCollectionEquality().hash(_blockStatusByMessageId),
  );

  /// Create a copy of ChatMessageMapperContext
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ChatMessageMapperContextImplCopyWith<_$ChatMessageMapperContextImpl>
  get copyWith =>
      __$$ChatMessageMapperContextImplCopyWithImpl<
        _$ChatMessageMapperContextImpl
      >(this, _$identity);
}

abstract class _ChatMessageMapperContext implements ChatMessageMapperContext {
  const factory _ChatMessageMapperContext({
    final String? currentCharName,
    final String? currentCharColor,
    final String? currentPersonaName,
    final String? charAvatarDataUrl,
    final String? personaAvatarDataUrl,
    required final bool isGenerating,
    final Set<String> coveredMemoryIds,
    final Set<String> pendingMemoryIds,
    final Set<String> draftMemoryIds,
    final int greetingTotal,
    final Map<String, String> blockStatusByMessageId,
  }) = _$ChatMessageMapperContextImpl;

  @override
  String? get currentCharName;
  @override
  String? get currentCharColor;
  @override
  String? get currentPersonaName;
  @override
  String? get charAvatarDataUrl;
  @override
  String? get personaAvatarDataUrl;
  @override
  bool get isGenerating;
  @override
  Set<String> get coveredMemoryIds;
  @override
  Set<String> get pendingMemoryIds;
  @override
  Set<String> get draftMemoryIds;
  @override
  int get greetingTotal;

  /// messageId → aggregated block status ('running'|'done'|'error')
  @override
  Map<String, String> get blockStatusByMessageId;

  /// Create a copy of ChatMessageMapperContext
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ChatMessageMapperContextImplCopyWith<_$ChatMessageMapperContextImpl>
  get copyWith => throw _privateConstructorUsedError;
}
