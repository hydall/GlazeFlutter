// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'api_config.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models');

ApiConfig _$ApiConfigFromJson(Map<String, dynamic> json) {
  return _ApiConfig.fromJson(json);
}

/// @nodoc
mixin _$ApiConfig {
  String get id => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  String get providerId => throw _privateConstructorUsedError;
  String get endpoint => throw _privateConstructorUsedError;
  String get apiKey => throw _privateConstructorUsedError;
  String get model => throw _privateConstructorUsedError;
  int get maxTokens => throw _privateConstructorUsedError;
  int get contextSize => throw _privateConstructorUsedError;
  double get temperature => throw _privateConstructorUsedError;
  double get topP => throw _privateConstructorUsedError;
  bool get stream => throw _privateConstructorUsedError;
  String get reasoningEffort => throw _privateConstructorUsedError;
  bool get requestReasoning => throw _privateConstructorUsedError;
  String? get reasoningTagStart => throw _privateConstructorUsedError;
  String? get reasoningTagEnd => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $ApiConfigCopyWith<ApiConfig> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ApiConfigCopyWith<$Res> {
  factory $ApiConfigCopyWith(ApiConfig value, $Res Function(ApiConfig) then) =
      _$ApiConfigCopyWithImpl<$Res, ApiConfig>;
  @useResult
  $Res call(
      {String id,
      String name,
      String providerId,
      String endpoint,
      String apiKey,
      String model,
      int maxTokens,
      int contextSize,
      double temperature,
      double topP,
      bool stream,
      String reasoningEffort,
      bool requestReasoning,
      String? reasoningTagStart,
      String? reasoningTagEnd});
}

/// @nodoc
class _$ApiConfigCopyWithImpl<$Res, $Val extends ApiConfig>
    implements $ApiConfigCopyWith<$Res> {
  _$ApiConfigCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? providerId = null,
    Object? endpoint = null,
    Object? apiKey = null,
    Object? model = null,
    Object? maxTokens = null,
    Object? contextSize = null,
    Object? temperature = null,
    Object? topP = null,
    Object? stream = null,
    Object? reasoningEffort = null,
    Object? requestReasoning = null,
    Object? reasoningTagStart = freezed,
    Object? reasoningTagEnd = freezed,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      providerId: null == providerId
          ? _value.providerId
          : providerId // ignore: cast_nullable_to_non_nullable
              as String,
      endpoint: null == endpoint
          ? _value.endpoint
          : endpoint // ignore: cast_nullable_to_non_nullable
              as String,
      apiKey: null == apiKey
          ? _value.apiKey
          : apiKey // ignore: cast_nullable_to_non_nullable
              as String,
      model: null == model
          ? _value.model
          : model // ignore: cast_nullable_to_non_nullable
              as String,
      maxTokens: null == maxTokens
          ? _value.maxTokens
          : maxTokens // ignore: cast_nullable_to_non_nullable
              as int,
      contextSize: null == contextSize
          ? _value.contextSize
          : contextSize // ignore: cast_nullable_to_non_nullable
              as int,
      temperature: null == temperature
          ? _value.temperature
          : temperature // ignore: cast_nullable_to_non_nullable
              as double,
      topP: null == topP
          ? _value.topP
          : topP // ignore: cast_nullable_to_non_nullable
              as double,
      stream: null == stream
          ? _value.stream
          : stream // ignore: cast_nullable_to_non_nullable
              as bool,
      reasoningEffort: null == reasoningEffort
          ? _value.reasoningEffort
          : reasoningEffort // ignore: cast_nullable_to_non_nullable
              as String,
      requestReasoning: null == requestReasoning
          ? _value.requestReasoning
          : requestReasoning // ignore: cast_nullable_to_non_nullable
              as bool,
      reasoningTagStart: freezed == reasoningTagStart
          ? _value.reasoningTagStart
          : reasoningTagStart // ignore: cast_nullable_to_non_nullable
              as String?,
      reasoningTagEnd: freezed == reasoningTagEnd
          ? _value.reasoningTagEnd
          : reasoningTagEnd // ignore: cast_nullable_to_non_nullable
              as String?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$ApiConfigImplCopyWith<$Res>
    implements $ApiConfigCopyWith<$Res> {
  factory _$$ApiConfigImplCopyWith(
          _$ApiConfigImpl value, $Res Function(_$ApiConfigImpl) then) =
      __$$ApiConfigImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      String name,
      String providerId,
      String endpoint,
      String apiKey,
      String model,
      int maxTokens,
      int contextSize,
      double temperature,
      double topP,
      bool stream,
      String reasoningEffort,
      bool requestReasoning,
      String? reasoningTagStart,
      String? reasoningTagEnd});
}

/// @nodoc
class __$$ApiConfigImplCopyWithImpl<$Res>
    extends _$ApiConfigCopyWithImpl<$Res, _$ApiConfigImpl>
    implements _$$ApiConfigImplCopyWith<$Res> {
  __$$ApiConfigImplCopyWithImpl(
      _$ApiConfigImpl _value, $Res Function(_$ApiConfigImpl) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? providerId = null,
    Object? endpoint = null,
    Object? apiKey = null,
    Object? model = null,
    Object? maxTokens = null,
    Object? contextSize = null,
    Object? temperature = null,
    Object? topP = null,
    Object? stream = null,
    Object? reasoningEffort = null,
    Object? requestReasoning = null,
    Object? reasoningTagStart = freezed,
    Object? reasoningTagEnd = freezed,
  }) {
    return _then(_$ApiConfigImpl(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      name: null == name
          ? _value.name
          : name // ignore: cast_nullable_to_non_nullable
              as String,
      providerId: null == providerId
          ? _value.providerId
          : providerId // ignore: cast_nullable_to_non_nullable
              as String,
      endpoint: null == endpoint
          ? _value.endpoint
          : endpoint // ignore: cast_nullable_to_non_nullable
              as String,
      apiKey: null == apiKey
          ? _value.apiKey
          : apiKey // ignore: cast_nullable_to_non_nullable
              as String,
      model: null == model
          ? _value.model
          : model // ignore: cast_nullable_to_non_nullable
              as String,
      maxTokens: null == maxTokens
          ? _value.maxTokens
          : maxTokens // ignore: cast_nullable_to_non_nullable
              as int,
      contextSize: null == contextSize
          ? _value.contextSize
          : contextSize // ignore: cast_nullable_to_non_nullable
              as int,
      temperature: null == temperature
          ? _value.temperature
          : temperature // ignore: cast_nullable_to_non_nullable
              as double,
      topP: null == topP
          ? _value.topP
          : topP // ignore: cast_nullable_to_non_nullable
              as double,
      stream: null == stream
          ? _value.stream
          : stream // ignore: cast_nullable_to_non_nullable
              as bool,
      reasoningEffort: null == reasoningEffort
          ? _value.reasoningEffort
          : reasoningEffort // ignore: cast_nullable_to_non_nullable
              as String,
      requestReasoning: null == requestReasoning
          ? _value.requestReasoning
          : requestReasoning // ignore: cast_nullable_to_non_nullable
              as bool,
      reasoningTagStart: freezed == reasoningTagStart
          ? _value.reasoningTagStart
          : reasoningTagStart // ignore: cast_nullable_to_non_nullable
              as String?,
      reasoningTagEnd: freezed == reasoningTagEnd
          ? _value.reasoningTagEnd
          : reasoningTagEnd // ignore: cast_nullable_to_non_nullable
              as String?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$ApiConfigImpl implements _ApiConfig {
  const _$ApiConfigImpl(
      {required this.id,
      this.name = '',
      this.providerId = 'openai_compatible',
      this.endpoint = '',
      this.apiKey = '',
      this.model = '',
      this.maxTokens = 8000,
      this.contextSize = 32000,
      this.temperature = 0.7,
      this.topP = 0.9,
      this.stream = true,
      this.reasoningEffort = 'medium',
      this.requestReasoning = false,
      this.reasoningTagStart,
      this.reasoningTagEnd});

  factory _$ApiConfigImpl.fromJson(Map<String, dynamic> json) =>
      _$$ApiConfigImplFromJson(json);

  @override
  final String id;
  @override
  @JsonKey()
  final String name;
  @override
  @JsonKey()
  final String providerId;
  @override
  @JsonKey()
  final String endpoint;
  @override
  @JsonKey()
  final String apiKey;
  @override
  @JsonKey()
  final String model;
  @override
  @JsonKey()
  final int maxTokens;
  @override
  @JsonKey()
  final int contextSize;
  @override
  @JsonKey()
  final double temperature;
  @override
  @JsonKey()
  final double topP;
  @override
  @JsonKey()
  final bool stream;
  @override
  @JsonKey()
  final String reasoningEffort;
  @override
  @JsonKey()
  final bool requestReasoning;
  @override
  final String? reasoningTagStart;
  @override
  final String? reasoningTagEnd;

  @override
  String toString() {
    return 'ApiConfig(id: $id, name: $name, providerId: $providerId, endpoint: $endpoint, apiKey: $apiKey, model: $model, maxTokens: $maxTokens, contextSize: $contextSize, temperature: $temperature, topP: $topP, stream: $stream, reasoningEffort: $reasoningEffort, requestReasoning: $requestReasoning, reasoningTagStart: $reasoningTagStart, reasoningTagEnd: $reasoningTagEnd)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ApiConfigImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.providerId, providerId) ||
                other.providerId == providerId) &&
            (identical(other.endpoint, endpoint) ||
                other.endpoint == endpoint) &&
            (identical(other.apiKey, apiKey) || other.apiKey == apiKey) &&
            (identical(other.model, model) || other.model == model) &&
            (identical(other.maxTokens, maxTokens) ||
                other.maxTokens == maxTokens) &&
            (identical(other.contextSize, contextSize) ||
                other.contextSize == contextSize) &&
            (identical(other.temperature, temperature) ||
                other.temperature == temperature) &&
            (identical(other.topP, topP) || other.topP == topP) &&
            (identical(other.stream, stream) || other.stream == stream) &&
            (identical(other.reasoningEffort, reasoningEffort) ||
                other.reasoningEffort == reasoningEffort) &&
            (identical(other.requestReasoning, requestReasoning) ||
                other.requestReasoning == requestReasoning) &&
            (identical(other.reasoningTagStart, reasoningTagStart) ||
                other.reasoningTagStart == reasoningTagStart) &&
            (identical(other.reasoningTagEnd, reasoningTagEnd) ||
                other.reasoningTagEnd == reasoningTagEnd));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      name,
      providerId,
      endpoint,
      apiKey,
      model,
      maxTokens,
      contextSize,
      temperature,
      topP,
      stream,
      reasoningEffort,
      requestReasoning,
      reasoningTagStart,
      reasoningTagEnd);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$ApiConfigImplCopyWith<_$ApiConfigImpl> get copyWith =>
      __$$ApiConfigImplCopyWithImpl<_$ApiConfigImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$ApiConfigImplToJson(
      this,
    );
  }
}

abstract class _ApiConfig implements ApiConfig {
  const factory _ApiConfig(
      {required final String id,
      final String name,
      final String providerId,
      final String endpoint,
      final String apiKey,
      final String model,
      final int maxTokens,
      final int contextSize,
      final double temperature,
      final double topP,
      final bool stream,
      final String reasoningEffort,
      final bool requestReasoning,
      final String? reasoningTagStart,
      final String? reasoningTagEnd}) = _$ApiConfigImpl;

  factory _ApiConfig.fromJson(Map<String, dynamic> json) =
      _$ApiConfigImpl.fromJson;

  @override
  String get id;
  @override
  String get name;
  @override
  String get providerId;
  @override
  String get endpoint;
  @override
  String get apiKey;
  @override
  String get model;
  @override
  int get maxTokens;
  @override
  int get contextSize;
  @override
  double get temperature;
  @override
  double get topP;
  @override
  bool get stream;
  @override
  String get reasoningEffort;
  @override
  bool get requestReasoning;
  @override
  String? get reasoningTagStart;
  @override
  String? get reasoningTagEnd;
  @override
  @JsonKey(ignore: true)
  _$$ApiConfigImplCopyWith<_$ApiConfigImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
