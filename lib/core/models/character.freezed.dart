// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'character.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

Character _$CharacterFromJson(Map<String, dynamic> json) {
  return _Character.fromJson(json);
}

/// @nodoc
mixin _$Character {
  String get id => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  String? get avatarPath => throw _privateConstructorUsedError;
  String? get description => throw _privateConstructorUsedError;
  String? get personality => throw _privateConstructorUsedError;
  String? get scenario => throw _privateConstructorUsedError;
  String? get firstMes => throw _privateConstructorUsedError;
  String? get mesExample => throw _privateConstructorUsedError;
  String? get systemPrompt => throw _privateConstructorUsedError;
  String? get postHistoryInstructions => throw _privateConstructorUsedError;
  String? get creator => throw _privateConstructorUsedError;
  String? get creatorNotes => throw _privateConstructorUsedError;
  List<String> get tags => throw _privateConstructorUsedError;
  List<String> get alternateGreetings => throw _privateConstructorUsedError;
  String? get color => throw _privateConstructorUsedError;
  int get updatedAt => throw _privateConstructorUsedError;

  /// Serializes this Character to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of Character
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $CharacterCopyWith<Character> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $CharacterCopyWith<$Res> {
  factory $CharacterCopyWith(Character value, $Res Function(Character) then) =
      _$CharacterCopyWithImpl<$Res, Character>;
  @useResult
  $Res call({
    String id,
    String name,
    String? avatarPath,
    String? description,
    String? personality,
    String? scenario,
    String? firstMes,
    String? mesExample,
    String? systemPrompt,
    String? postHistoryInstructions,
    String? creator,
    String? creatorNotes,
    List<String> tags,
    List<String> alternateGreetings,
    String? color,
    int updatedAt,
  });
}

/// @nodoc
class _$CharacterCopyWithImpl<$Res, $Val extends Character>
    implements $CharacterCopyWith<$Res> {
  _$CharacterCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of Character
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? avatarPath = freezed,
    Object? description = freezed,
    Object? personality = freezed,
    Object? scenario = freezed,
    Object? firstMes = freezed,
    Object? mesExample = freezed,
    Object? systemPrompt = freezed,
    Object? postHistoryInstructions = freezed,
    Object? creator = freezed,
    Object? creatorNotes = freezed,
    Object? tags = null,
    Object? alternateGreetings = null,
    Object? color = freezed,
    Object? updatedAt = null,
  }) {
    return _then(
      _value.copyWith(
            id: null == id
                ? _value.id
                : id // ignore: cast_nullable_to_non_nullable
                      as String,
            name: null == name
                ? _value.name
                : name // ignore: cast_nullable_to_non_nullable
                      as String,
            avatarPath: freezed == avatarPath
                ? _value.avatarPath
                : avatarPath // ignore: cast_nullable_to_non_nullable
                      as String?,
            description: freezed == description
                ? _value.description
                : description // ignore: cast_nullable_to_non_nullable
                      as String?,
            personality: freezed == personality
                ? _value.personality
                : personality // ignore: cast_nullable_to_non_nullable
                      as String?,
            scenario: freezed == scenario
                ? _value.scenario
                : scenario // ignore: cast_nullable_to_non_nullable
                      as String?,
            firstMes: freezed == firstMes
                ? _value.firstMes
                : firstMes // ignore: cast_nullable_to_non_nullable
                      as String?,
            mesExample: freezed == mesExample
                ? _value.mesExample
                : mesExample // ignore: cast_nullable_to_non_nullable
                      as String?,
            systemPrompt: freezed == systemPrompt
                ? _value.systemPrompt
                : systemPrompt // ignore: cast_nullable_to_non_nullable
                      as String?,
            postHistoryInstructions: freezed == postHistoryInstructions
                ? _value.postHistoryInstructions
                : postHistoryInstructions // ignore: cast_nullable_to_non_nullable
                      as String?,
            creator: freezed == creator
                ? _value.creator
                : creator // ignore: cast_nullable_to_non_nullable
                      as String?,
            creatorNotes: freezed == creatorNotes
                ? _value.creatorNotes
                : creatorNotes // ignore: cast_nullable_to_non_nullable
                      as String?,
            tags: null == tags
                ? _value.tags
                : tags // ignore: cast_nullable_to_non_nullable
                      as List<String>,
            alternateGreetings: null == alternateGreetings
                ? _value.alternateGreetings
                : alternateGreetings // ignore: cast_nullable_to_non_nullable
                      as List<String>,
            color: freezed == color
                ? _value.color
                : color // ignore: cast_nullable_to_non_nullable
                      as String?,
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
abstract class _$$CharacterImplCopyWith<$Res>
    implements $CharacterCopyWith<$Res> {
  factory _$$CharacterImplCopyWith(
    _$CharacterImpl value,
    $Res Function(_$CharacterImpl) then,
  ) = __$$CharacterImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String id,
    String name,
    String? avatarPath,
    String? description,
    String? personality,
    String? scenario,
    String? firstMes,
    String? mesExample,
    String? systemPrompt,
    String? postHistoryInstructions,
    String? creator,
    String? creatorNotes,
    List<String> tags,
    List<String> alternateGreetings,
    String? color,
    int updatedAt,
  });
}

/// @nodoc
class __$$CharacterImplCopyWithImpl<$Res>
    extends _$CharacterCopyWithImpl<$Res, _$CharacterImpl>
    implements _$$CharacterImplCopyWith<$Res> {
  __$$CharacterImplCopyWithImpl(
    _$CharacterImpl _value,
    $Res Function(_$CharacterImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of Character
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? avatarPath = freezed,
    Object? description = freezed,
    Object? personality = freezed,
    Object? scenario = freezed,
    Object? firstMes = freezed,
    Object? mesExample = freezed,
    Object? systemPrompt = freezed,
    Object? postHistoryInstructions = freezed,
    Object? creator = freezed,
    Object? creatorNotes = freezed,
    Object? tags = null,
    Object? alternateGreetings = null,
    Object? color = freezed,
    Object? updatedAt = null,
  }) {
    return _then(
      _$CharacterImpl(
        id: null == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String,
        name: null == name
            ? _value.name
            : name // ignore: cast_nullable_to_non_nullable
                  as String,
        avatarPath: freezed == avatarPath
            ? _value.avatarPath
            : avatarPath // ignore: cast_nullable_to_non_nullable
                  as String?,
        description: freezed == description
            ? _value.description
            : description // ignore: cast_nullable_to_non_nullable
                  as String?,
        personality: freezed == personality
            ? _value.personality
            : personality // ignore: cast_nullable_to_non_nullable
                  as String?,
        scenario: freezed == scenario
            ? _value.scenario
            : scenario // ignore: cast_nullable_to_non_nullable
                  as String?,
        firstMes: freezed == firstMes
            ? _value.firstMes
            : firstMes // ignore: cast_nullable_to_non_nullable
                  as String?,
        mesExample: freezed == mesExample
            ? _value.mesExample
            : mesExample // ignore: cast_nullable_to_non_nullable
                  as String?,
        systemPrompt: freezed == systemPrompt
            ? _value.systemPrompt
            : systemPrompt // ignore: cast_nullable_to_non_nullable
                  as String?,
        postHistoryInstructions: freezed == postHistoryInstructions
            ? _value.postHistoryInstructions
            : postHistoryInstructions // ignore: cast_nullable_to_non_nullable
                  as String?,
        creator: freezed == creator
            ? _value.creator
            : creator // ignore: cast_nullable_to_non_nullable
                  as String?,
        creatorNotes: freezed == creatorNotes
            ? _value.creatorNotes
            : creatorNotes // ignore: cast_nullable_to_non_nullable
                  as String?,
        tags: null == tags
            ? _value._tags
            : tags // ignore: cast_nullable_to_non_nullable
                  as List<String>,
        alternateGreetings: null == alternateGreetings
            ? _value._alternateGreetings
            : alternateGreetings // ignore: cast_nullable_to_non_nullable
                  as List<String>,
        color: freezed == color
            ? _value.color
            : color // ignore: cast_nullable_to_non_nullable
                  as String?,
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
class _$CharacterImpl implements _Character {
  const _$CharacterImpl({
    required this.id,
    required this.name,
    this.avatarPath,
    this.description,
    this.personality,
    this.scenario,
    this.firstMes,
    this.mesExample,
    this.systemPrompt,
    this.postHistoryInstructions,
    this.creator,
    this.creatorNotes,
    final List<String> tags = const [],
    final List<String> alternateGreetings = const [],
    this.color,
    this.updatedAt = 0,
  }) : _tags = tags,
       _alternateGreetings = alternateGreetings;

  factory _$CharacterImpl.fromJson(Map<String, dynamic> json) =>
      _$$CharacterImplFromJson(json);

  @override
  final String id;
  @override
  final String name;
  @override
  final String? avatarPath;
  @override
  final String? description;
  @override
  final String? personality;
  @override
  final String? scenario;
  @override
  final String? firstMes;
  @override
  final String? mesExample;
  @override
  final String? systemPrompt;
  @override
  final String? postHistoryInstructions;
  @override
  final String? creator;
  @override
  final String? creatorNotes;
  final List<String> _tags;
  @override
  @JsonKey()
  List<String> get tags {
    if (_tags is EqualUnmodifiableListView) return _tags;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_tags);
  }

  final List<String> _alternateGreetings;
  @override
  @JsonKey()
  List<String> get alternateGreetings {
    if (_alternateGreetings is EqualUnmodifiableListView)
      return _alternateGreetings;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_alternateGreetings);
  }

  @override
  final String? color;
  @override
  @JsonKey()
  final int updatedAt;

  @override
  String toString() {
    return 'Character(id: $id, name: $name, avatarPath: $avatarPath, description: $description, personality: $personality, scenario: $scenario, firstMes: $firstMes, mesExample: $mesExample, systemPrompt: $systemPrompt, postHistoryInstructions: $postHistoryInstructions, creator: $creator, creatorNotes: $creatorNotes, tags: $tags, alternateGreetings: $alternateGreetings, color: $color, updatedAt: $updatedAt)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$CharacterImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.avatarPath, avatarPath) ||
                other.avatarPath == avatarPath) &&
            (identical(other.description, description) ||
                other.description == description) &&
            (identical(other.personality, personality) ||
                other.personality == personality) &&
            (identical(other.scenario, scenario) ||
                other.scenario == scenario) &&
            (identical(other.firstMes, firstMes) ||
                other.firstMes == firstMes) &&
            (identical(other.mesExample, mesExample) ||
                other.mesExample == mesExample) &&
            (identical(other.systemPrompt, systemPrompt) ||
                other.systemPrompt == systemPrompt) &&
            (identical(
                  other.postHistoryInstructions,
                  postHistoryInstructions,
                ) ||
                other.postHistoryInstructions == postHistoryInstructions) &&
            (identical(other.creator, creator) || other.creator == creator) &&
            (identical(other.creatorNotes, creatorNotes) ||
                other.creatorNotes == creatorNotes) &&
            const DeepCollectionEquality().equals(other._tags, _tags) &&
            const DeepCollectionEquality().equals(
              other._alternateGreetings,
              _alternateGreetings,
            ) &&
            (identical(other.color, color) || other.color == color) &&
            (identical(other.updatedAt, updatedAt) ||
                other.updatedAt == updatedAt));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
    runtimeType,
    id,
    name,
    avatarPath,
    description,
    personality,
    scenario,
    firstMes,
    mesExample,
    systemPrompt,
    postHistoryInstructions,
    creator,
    creatorNotes,
    const DeepCollectionEquality().hash(_tags),
    const DeepCollectionEquality().hash(_alternateGreetings),
    color,
    updatedAt,
  );

  /// Create a copy of Character
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$CharacterImplCopyWith<_$CharacterImpl> get copyWith =>
      __$$CharacterImplCopyWithImpl<_$CharacterImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$CharacterImplToJson(this);
  }
}

abstract class _Character implements Character {
  const factory _Character({
    required final String id,
    required final String name,
    final String? avatarPath,
    final String? description,
    final String? personality,
    final String? scenario,
    final String? firstMes,
    final String? mesExample,
    final String? systemPrompt,
    final String? postHistoryInstructions,
    final String? creator,
    final String? creatorNotes,
    final List<String> tags,
    final List<String> alternateGreetings,
    final String? color,
    final int updatedAt,
  }) = _$CharacterImpl;

  factory _Character.fromJson(Map<String, dynamic> json) =
      _$CharacterImpl.fromJson;

  @override
  String get id;
  @override
  String get name;
  @override
  String? get avatarPath;
  @override
  String? get description;
  @override
  String? get personality;
  @override
  String? get scenario;
  @override
  String? get firstMes;
  @override
  String? get mesExample;
  @override
  String? get systemPrompt;
  @override
  String? get postHistoryInstructions;
  @override
  String? get creator;
  @override
  String? get creatorNotes;
  @override
  List<String> get tags;
  @override
  List<String> get alternateGreetings;
  @override
  String? get color;
  @override
  int get updatedAt;

  /// Create a copy of Character
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$CharacterImplCopyWith<_$CharacterImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
