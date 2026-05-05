import 'package:freezed_annotation/freezed_annotation.dart';

part 'persona.freezed.dart';
part 'persona.g.dart';

@freezed
class Persona with _$Persona {
  const factory Persona({
    required String id,
    required String name,
    String? prompt,
    String? avatarPath,
  }) = _Persona;

  factory Persona.fromJson(Map<String, dynamic> json) =>
      _$PersonaFromJson(json);
}
