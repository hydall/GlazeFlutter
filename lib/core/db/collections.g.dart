// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'collections.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetCharacterCollectionCollection on Isar {
  IsarCollection<CharacterCollection> get characterCollections =>
      this.collection();
}

const CharacterCollectionSchema = CollectionSchema(
  name: r'CharacterCollection',
  id: 199425130056149268,
  properties: {
    r'alternateGreetingsJson': PropertySchema(
      id: 0,
      name: r'alternateGreetingsJson',
      type: IsarType.string,
    ),
    r'avatarPath': PropertySchema(
      id: 1,
      name: r'avatarPath',
      type: IsarType.string,
    ),
    r'charId': PropertySchema(
      id: 2,
      name: r'charId',
      type: IsarType.string,
    ),
    r'color': PropertySchema(
      id: 3,
      name: r'color',
      type: IsarType.string,
    ),
    r'creator': PropertySchema(
      id: 4,
      name: r'creator',
      type: IsarType.string,
    ),
    r'creatorNotes': PropertySchema(
      id: 5,
      name: r'creatorNotes',
      type: IsarType.string,
    ),
    r'description': PropertySchema(
      id: 6,
      name: r'description',
      type: IsarType.string,
    ),
    r'firstMes': PropertySchema(
      id: 7,
      name: r'firstMes',
      type: IsarType.string,
    ),
    r'mesExample': PropertySchema(
      id: 8,
      name: r'mesExample',
      type: IsarType.string,
    ),
    r'name': PropertySchema(
      id: 9,
      name: r'name',
      type: IsarType.string,
    ),
    r'personality': PropertySchema(
      id: 10,
      name: r'personality',
      type: IsarType.string,
    ),
    r'postHistoryInstructions': PropertySchema(
      id: 11,
      name: r'postHistoryInstructions',
      type: IsarType.string,
    ),
    r'scenario': PropertySchema(
      id: 12,
      name: r'scenario',
      type: IsarType.string,
    ),
    r'systemPrompt': PropertySchema(
      id: 13,
      name: r'systemPrompt',
      type: IsarType.string,
    ),
    r'tagsJson': PropertySchema(
      id: 14,
      name: r'tagsJson',
      type: IsarType.string,
    ),
    r'updatedAt': PropertySchema(
      id: 15,
      name: r'updatedAt',
      type: IsarType.long,
    )
  },
  estimateSize: _characterCollectionEstimateSize,
  serialize: _characterCollectionSerialize,
  deserialize: _characterCollectionDeserialize,
  deserializeProp: _characterCollectionDeserializeProp,
  idName: r'id',
  indexes: {
    r'charId': IndexSchema(
      id: -6102374525663439255,
      name: r'charId',
      unique: true,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'charId',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _characterCollectionGetId,
  getLinks: _characterCollectionGetLinks,
  attach: _characterCollectionAttach,
  version: '3.1.0+1',
);

int _characterCollectionEstimateSize(
  CharacterCollection object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  {
    final value = object.alternateGreetingsJson;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.avatarPath;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.charId.length * 3;
  {
    final value = object.color;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.creator;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.creatorNotes;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.description;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.firstMes;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.mesExample;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.name.length * 3;
  {
    final value = object.personality;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.postHistoryInstructions;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.scenario;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.systemPrompt;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.tagsJson;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  return bytesCount;
}

void _characterCollectionSerialize(
  CharacterCollection object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.alternateGreetingsJson);
  writer.writeString(offsets[1], object.avatarPath);
  writer.writeString(offsets[2], object.charId);
  writer.writeString(offsets[3], object.color);
  writer.writeString(offsets[4], object.creator);
  writer.writeString(offsets[5], object.creatorNotes);
  writer.writeString(offsets[6], object.description);
  writer.writeString(offsets[7], object.firstMes);
  writer.writeString(offsets[8], object.mesExample);
  writer.writeString(offsets[9], object.name);
  writer.writeString(offsets[10], object.personality);
  writer.writeString(offsets[11], object.postHistoryInstructions);
  writer.writeString(offsets[12], object.scenario);
  writer.writeString(offsets[13], object.systemPrompt);
  writer.writeString(offsets[14], object.tagsJson);
  writer.writeLong(offsets[15], object.updatedAt);
}

CharacterCollection _characterCollectionDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = CharacterCollection();
  object.alternateGreetingsJson = reader.readStringOrNull(offsets[0]);
  object.avatarPath = reader.readStringOrNull(offsets[1]);
  object.charId = reader.readString(offsets[2]);
  object.color = reader.readStringOrNull(offsets[3]);
  object.creator = reader.readStringOrNull(offsets[4]);
  object.creatorNotes = reader.readStringOrNull(offsets[5]);
  object.description = reader.readStringOrNull(offsets[6]);
  object.firstMes = reader.readStringOrNull(offsets[7]);
  object.id = id;
  object.mesExample = reader.readStringOrNull(offsets[8]);
  object.name = reader.readString(offsets[9]);
  object.personality = reader.readStringOrNull(offsets[10]);
  object.postHistoryInstructions = reader.readStringOrNull(offsets[11]);
  object.scenario = reader.readStringOrNull(offsets[12]);
  object.systemPrompt = reader.readStringOrNull(offsets[13]);
  object.tagsJson = reader.readStringOrNull(offsets[14]);
  object.updatedAt = reader.readLong(offsets[15]);
  return object;
}

P _characterCollectionDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readStringOrNull(offset)) as P;
    case 1:
      return (reader.readStringOrNull(offset)) as P;
    case 2:
      return (reader.readString(offset)) as P;
    case 3:
      return (reader.readStringOrNull(offset)) as P;
    case 4:
      return (reader.readStringOrNull(offset)) as P;
    case 5:
      return (reader.readStringOrNull(offset)) as P;
    case 6:
      return (reader.readStringOrNull(offset)) as P;
    case 7:
      return (reader.readStringOrNull(offset)) as P;
    case 8:
      return (reader.readStringOrNull(offset)) as P;
    case 9:
      return (reader.readString(offset)) as P;
    case 10:
      return (reader.readStringOrNull(offset)) as P;
    case 11:
      return (reader.readStringOrNull(offset)) as P;
    case 12:
      return (reader.readStringOrNull(offset)) as P;
    case 13:
      return (reader.readStringOrNull(offset)) as P;
    case 14:
      return (reader.readStringOrNull(offset)) as P;
    case 15:
      return (reader.readLong(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _characterCollectionGetId(CharacterCollection object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _characterCollectionGetLinks(
    CharacterCollection object) {
  return [];
}

void _characterCollectionAttach(
    IsarCollection<dynamic> col, Id id, CharacterCollection object) {
  object.id = id;
}

extension CharacterCollectionByIndex on IsarCollection<CharacterCollection> {
  Future<CharacterCollection?> getByCharId(String charId) {
    return getByIndex(r'charId', [charId]);
  }

  CharacterCollection? getByCharIdSync(String charId) {
    return getByIndexSync(r'charId', [charId]);
  }

  Future<bool> deleteByCharId(String charId) {
    return deleteByIndex(r'charId', [charId]);
  }

  bool deleteByCharIdSync(String charId) {
    return deleteByIndexSync(r'charId', [charId]);
  }

  Future<List<CharacterCollection?>> getAllByCharId(List<String> charIdValues) {
    final values = charIdValues.map((e) => [e]).toList();
    return getAllByIndex(r'charId', values);
  }

  List<CharacterCollection?> getAllByCharIdSync(List<String> charIdValues) {
    final values = charIdValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'charId', values);
  }

  Future<int> deleteAllByCharId(List<String> charIdValues) {
    final values = charIdValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'charId', values);
  }

  int deleteAllByCharIdSync(List<String> charIdValues) {
    final values = charIdValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'charId', values);
  }

  Future<Id> putByCharId(CharacterCollection object) {
    return putByIndex(r'charId', object);
  }

  Id putByCharIdSync(CharacterCollection object, {bool saveLinks = true}) {
    return putByIndexSync(r'charId', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByCharId(List<CharacterCollection> objects) {
    return putAllByIndex(r'charId', objects);
  }

  List<Id> putAllByCharIdSync(List<CharacterCollection> objects,
      {bool saveLinks = true}) {
    return putAllByIndexSync(r'charId', objects, saveLinks: saveLinks);
  }
}

extension CharacterCollectionQueryWhereSort
    on QueryBuilder<CharacterCollection, CharacterCollection, QWhere> {
  QueryBuilder<CharacterCollection, CharacterCollection, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension CharacterCollectionQueryWhere
    on QueryBuilder<CharacterCollection, CharacterCollection, QWhereClause> {
  QueryBuilder<CharacterCollection, CharacterCollection, QAfterWhereClause>
      idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterWhereClause>
      idNotEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterWhereClause>
      idGreaterThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterWhereClause>
      idLessThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterWhereClause>
      idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: lowerId,
        includeLower: includeLower,
        upper: upperId,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterWhereClause>
      charIdEqualTo(String charId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'charId',
        value: [charId],
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterWhereClause>
      charIdNotEqualTo(String charId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'charId',
              lower: [],
              upper: [charId],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'charId',
              lower: [charId],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'charId',
              lower: [charId],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'charId',
              lower: [],
              upper: [charId],
              includeUpper: false,
            ));
      }
    });
  }
}

extension CharacterCollectionQueryFilter on QueryBuilder<CharacterCollection,
    CharacterCollection, QFilterCondition> {
  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      alternateGreetingsJsonIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'alternateGreetingsJson',
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      alternateGreetingsJsonIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'alternateGreetingsJson',
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      alternateGreetingsJsonEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'alternateGreetingsJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      alternateGreetingsJsonGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'alternateGreetingsJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      alternateGreetingsJsonLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'alternateGreetingsJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      alternateGreetingsJsonBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'alternateGreetingsJson',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      alternateGreetingsJsonStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'alternateGreetingsJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      alternateGreetingsJsonEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'alternateGreetingsJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      alternateGreetingsJsonContains(String value,
          {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'alternateGreetingsJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      alternateGreetingsJsonMatches(String pattern,
          {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'alternateGreetingsJson',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      alternateGreetingsJsonIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'alternateGreetingsJson',
        value: '',
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      alternateGreetingsJsonIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'alternateGreetingsJson',
        value: '',
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      avatarPathIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'avatarPath',
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      avatarPathIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'avatarPath',
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      avatarPathEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'avatarPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      avatarPathGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'avatarPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      avatarPathLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'avatarPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      avatarPathBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'avatarPath',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      avatarPathStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'avatarPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      avatarPathEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'avatarPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      avatarPathContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'avatarPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      avatarPathMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'avatarPath',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      avatarPathIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'avatarPath',
        value: '',
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      avatarPathIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'avatarPath',
        value: '',
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      charIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'charId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      charIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'charId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      charIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'charId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      charIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'charId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      charIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'charId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      charIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'charId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      charIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'charId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      charIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'charId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      charIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'charId',
        value: '',
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      charIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'charId',
        value: '',
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      colorIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'color',
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      colorIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'color',
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      colorEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'color',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      colorGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'color',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      colorLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'color',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      colorBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'color',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      colorStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'color',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      colorEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'color',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      colorContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'color',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      colorMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'color',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      colorIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'color',
        value: '',
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      colorIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'color',
        value: '',
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      creatorIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'creator',
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      creatorIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'creator',
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      creatorEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'creator',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      creatorGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'creator',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      creatorLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'creator',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      creatorBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'creator',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      creatorStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'creator',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      creatorEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'creator',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      creatorContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'creator',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      creatorMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'creator',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      creatorIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'creator',
        value: '',
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      creatorIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'creator',
        value: '',
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      creatorNotesIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'creatorNotes',
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      creatorNotesIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'creatorNotes',
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      creatorNotesEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'creatorNotes',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      creatorNotesGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'creatorNotes',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      creatorNotesLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'creatorNotes',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      creatorNotesBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'creatorNotes',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      creatorNotesStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'creatorNotes',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      creatorNotesEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'creatorNotes',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      creatorNotesContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'creatorNotes',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      creatorNotesMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'creatorNotes',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      creatorNotesIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'creatorNotes',
        value: '',
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      creatorNotesIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'creatorNotes',
        value: '',
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      descriptionIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'description',
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      descriptionIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'description',
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      descriptionEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'description',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      descriptionGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'description',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      descriptionLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'description',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      descriptionBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'description',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      descriptionStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'description',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      descriptionEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'description',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      descriptionContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'description',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      descriptionMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'description',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      descriptionIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'description',
        value: '',
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      descriptionIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'description',
        value: '',
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      firstMesIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'firstMes',
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      firstMesIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'firstMes',
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      firstMesEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'firstMes',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      firstMesGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'firstMes',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      firstMesLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'firstMes',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      firstMesBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'firstMes',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      firstMesStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'firstMes',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      firstMesEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'firstMes',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      firstMesContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'firstMes',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      firstMesMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'firstMes',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      firstMesIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'firstMes',
        value: '',
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      firstMesIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'firstMes',
        value: '',
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      idEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      idGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'id',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      mesExampleIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'mesExample',
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      mesExampleIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'mesExample',
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      mesExampleEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'mesExample',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      mesExampleGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'mesExample',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      mesExampleLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'mesExample',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      mesExampleBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'mesExample',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      mesExampleStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'mesExample',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      mesExampleEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'mesExample',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      mesExampleContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'mesExample',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      mesExampleMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'mesExample',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      mesExampleIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'mesExample',
        value: '',
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      mesExampleIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'mesExample',
        value: '',
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      nameEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      nameGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      nameLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      nameBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'name',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      nameStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      nameEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      nameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      nameMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'name',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      nameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'name',
        value: '',
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      nameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'name',
        value: '',
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      personalityIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'personality',
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      personalityIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'personality',
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      personalityEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'personality',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      personalityGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'personality',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      personalityLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'personality',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      personalityBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'personality',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      personalityStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'personality',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      personalityEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'personality',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      personalityContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'personality',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      personalityMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'personality',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      personalityIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'personality',
        value: '',
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      personalityIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'personality',
        value: '',
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      postHistoryInstructionsIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'postHistoryInstructions',
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      postHistoryInstructionsIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'postHistoryInstructions',
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      postHistoryInstructionsEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'postHistoryInstructions',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      postHistoryInstructionsGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'postHistoryInstructions',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      postHistoryInstructionsLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'postHistoryInstructions',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      postHistoryInstructionsBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'postHistoryInstructions',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      postHistoryInstructionsStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'postHistoryInstructions',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      postHistoryInstructionsEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'postHistoryInstructions',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      postHistoryInstructionsContains(String value,
          {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'postHistoryInstructions',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      postHistoryInstructionsMatches(String pattern,
          {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'postHistoryInstructions',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      postHistoryInstructionsIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'postHistoryInstructions',
        value: '',
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      postHistoryInstructionsIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'postHistoryInstructions',
        value: '',
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      scenarioIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'scenario',
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      scenarioIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'scenario',
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      scenarioEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'scenario',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      scenarioGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'scenario',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      scenarioLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'scenario',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      scenarioBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'scenario',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      scenarioStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'scenario',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      scenarioEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'scenario',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      scenarioContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'scenario',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      scenarioMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'scenario',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      scenarioIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'scenario',
        value: '',
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      scenarioIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'scenario',
        value: '',
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      systemPromptIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'systemPrompt',
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      systemPromptIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'systemPrompt',
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      systemPromptEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'systemPrompt',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      systemPromptGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'systemPrompt',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      systemPromptLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'systemPrompt',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      systemPromptBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'systemPrompt',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      systemPromptStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'systemPrompt',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      systemPromptEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'systemPrompt',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      systemPromptContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'systemPrompt',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      systemPromptMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'systemPrompt',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      systemPromptIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'systemPrompt',
        value: '',
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      systemPromptIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'systemPrompt',
        value: '',
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      tagsJsonIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'tagsJson',
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      tagsJsonIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'tagsJson',
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      tagsJsonEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'tagsJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      tagsJsonGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'tagsJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      tagsJsonLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'tagsJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      tagsJsonBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'tagsJson',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      tagsJsonStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'tagsJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      tagsJsonEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'tagsJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      tagsJsonContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'tagsJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      tagsJsonMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'tagsJson',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      tagsJsonIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'tagsJson',
        value: '',
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      tagsJsonIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'tagsJson',
        value: '',
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      updatedAtEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'updatedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      updatedAtGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'updatedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      updatedAtLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'updatedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterFilterCondition>
      updatedAtBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'updatedAt',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }
}

extension CharacterCollectionQueryObject on QueryBuilder<CharacterCollection,
    CharacterCollection, QFilterCondition> {}

extension CharacterCollectionQueryLinks on QueryBuilder<CharacterCollection,
    CharacterCollection, QFilterCondition> {}

extension CharacterCollectionQuerySortBy
    on QueryBuilder<CharacterCollection, CharacterCollection, QSortBy> {
  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      sortByAlternateGreetingsJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'alternateGreetingsJson', Sort.asc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      sortByAlternateGreetingsJsonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'alternateGreetingsJson', Sort.desc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      sortByAvatarPath() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'avatarPath', Sort.asc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      sortByAvatarPathDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'avatarPath', Sort.desc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      sortByCharId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'charId', Sort.asc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      sortByCharIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'charId', Sort.desc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      sortByColor() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'color', Sort.asc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      sortByColorDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'color', Sort.desc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      sortByCreator() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'creator', Sort.asc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      sortByCreatorDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'creator', Sort.desc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      sortByCreatorNotes() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'creatorNotes', Sort.asc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      sortByCreatorNotesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'creatorNotes', Sort.desc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      sortByDescription() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'description', Sort.asc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      sortByDescriptionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'description', Sort.desc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      sortByFirstMes() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'firstMes', Sort.asc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      sortByFirstMesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'firstMes', Sort.desc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      sortByMesExample() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mesExample', Sort.asc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      sortByMesExampleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mesExample', Sort.desc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      sortByName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.asc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      sortByNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.desc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      sortByPersonality() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'personality', Sort.asc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      sortByPersonalityDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'personality', Sort.desc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      sortByPostHistoryInstructions() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'postHistoryInstructions', Sort.asc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      sortByPostHistoryInstructionsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'postHistoryInstructions', Sort.desc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      sortByScenario() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'scenario', Sort.asc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      sortByScenarioDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'scenario', Sort.desc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      sortBySystemPrompt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'systemPrompt', Sort.asc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      sortBySystemPromptDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'systemPrompt', Sort.desc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      sortByTagsJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'tagsJson', Sort.asc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      sortByTagsJsonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'tagsJson', Sort.desc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      sortByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      sortByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }
}

extension CharacterCollectionQuerySortThenBy
    on QueryBuilder<CharacterCollection, CharacterCollection, QSortThenBy> {
  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      thenByAlternateGreetingsJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'alternateGreetingsJson', Sort.asc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      thenByAlternateGreetingsJsonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'alternateGreetingsJson', Sort.desc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      thenByAvatarPath() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'avatarPath', Sort.asc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      thenByAvatarPathDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'avatarPath', Sort.desc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      thenByCharId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'charId', Sort.asc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      thenByCharIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'charId', Sort.desc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      thenByColor() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'color', Sort.asc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      thenByColorDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'color', Sort.desc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      thenByCreator() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'creator', Sort.asc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      thenByCreatorDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'creator', Sort.desc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      thenByCreatorNotes() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'creatorNotes', Sort.asc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      thenByCreatorNotesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'creatorNotes', Sort.desc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      thenByDescription() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'description', Sort.asc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      thenByDescriptionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'description', Sort.desc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      thenByFirstMes() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'firstMes', Sort.asc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      thenByFirstMesDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'firstMes', Sort.desc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      thenByMesExample() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mesExample', Sort.asc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      thenByMesExampleDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mesExample', Sort.desc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      thenByName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.asc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      thenByNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.desc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      thenByPersonality() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'personality', Sort.asc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      thenByPersonalityDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'personality', Sort.desc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      thenByPostHistoryInstructions() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'postHistoryInstructions', Sort.asc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      thenByPostHistoryInstructionsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'postHistoryInstructions', Sort.desc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      thenByScenario() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'scenario', Sort.asc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      thenByScenarioDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'scenario', Sort.desc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      thenBySystemPrompt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'systemPrompt', Sort.asc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      thenBySystemPromptDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'systemPrompt', Sort.desc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      thenByTagsJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'tagsJson', Sort.asc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      thenByTagsJsonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'tagsJson', Sort.desc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      thenByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QAfterSortBy>
      thenByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }
}

extension CharacterCollectionQueryWhereDistinct
    on QueryBuilder<CharacterCollection, CharacterCollection, QDistinct> {
  QueryBuilder<CharacterCollection, CharacterCollection, QDistinct>
      distinctByAlternateGreetingsJson({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'alternateGreetingsJson',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QDistinct>
      distinctByAvatarPath({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'avatarPath', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QDistinct>
      distinctByCharId({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'charId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QDistinct>
      distinctByColor({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'color', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QDistinct>
      distinctByCreator({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'creator', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QDistinct>
      distinctByCreatorNotes({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'creatorNotes', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QDistinct>
      distinctByDescription({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'description', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QDistinct>
      distinctByFirstMes({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'firstMes', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QDistinct>
      distinctByMesExample({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'mesExample', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QDistinct>
      distinctByName({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'name', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QDistinct>
      distinctByPersonality({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'personality', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QDistinct>
      distinctByPostHistoryInstructions({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'postHistoryInstructions',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QDistinct>
      distinctByScenario({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'scenario', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QDistinct>
      distinctBySystemPrompt({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'systemPrompt', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QDistinct>
      distinctByTagsJson({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'tagsJson', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<CharacterCollection, CharacterCollection, QDistinct>
      distinctByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'updatedAt');
    });
  }
}

extension CharacterCollectionQueryProperty
    on QueryBuilder<CharacterCollection, CharacterCollection, QQueryProperty> {
  QueryBuilder<CharacterCollection, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<CharacterCollection, String?, QQueryOperations>
      alternateGreetingsJsonProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'alternateGreetingsJson');
    });
  }

  QueryBuilder<CharacterCollection, String?, QQueryOperations>
      avatarPathProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'avatarPath');
    });
  }

  QueryBuilder<CharacterCollection, String, QQueryOperations> charIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'charId');
    });
  }

  QueryBuilder<CharacterCollection, String?, QQueryOperations> colorProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'color');
    });
  }

  QueryBuilder<CharacterCollection, String?, QQueryOperations>
      creatorProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'creator');
    });
  }

  QueryBuilder<CharacterCollection, String?, QQueryOperations>
      creatorNotesProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'creatorNotes');
    });
  }

  QueryBuilder<CharacterCollection, String?, QQueryOperations>
      descriptionProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'description');
    });
  }

  QueryBuilder<CharacterCollection, String?, QQueryOperations>
      firstMesProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'firstMes');
    });
  }

  QueryBuilder<CharacterCollection, String?, QQueryOperations>
      mesExampleProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'mesExample');
    });
  }

  QueryBuilder<CharacterCollection, String, QQueryOperations> nameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'name');
    });
  }

  QueryBuilder<CharacterCollection, String?, QQueryOperations>
      personalityProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'personality');
    });
  }

  QueryBuilder<CharacterCollection, String?, QQueryOperations>
      postHistoryInstructionsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'postHistoryInstructions');
    });
  }

  QueryBuilder<CharacterCollection, String?, QQueryOperations>
      scenarioProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'scenario');
    });
  }

  QueryBuilder<CharacterCollection, String?, QQueryOperations>
      systemPromptProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'systemPrompt');
    });
  }

  QueryBuilder<CharacterCollection, String?, QQueryOperations>
      tagsJsonProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'tagsJson');
    });
  }

  QueryBuilder<CharacterCollection, int, QQueryOperations> updatedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'updatedAt');
    });
  }
}

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetChatSessionCollectionCollection on Isar {
  IsarCollection<ChatSessionCollection> get chatSessionCollections =>
      this.collection();
}

const ChatSessionCollectionSchema = CollectionSchema(
  name: r'ChatSessionCollection',
  id: 655546595088682502,
  properties: {
    r'characterId': PropertySchema(
      id: 0,
      name: r'characterId',
      type: IsarType.string,
    ),
    r'messagesJson': PropertySchema(
      id: 1,
      name: r'messagesJson',
      type: IsarType.string,
    ),
    r'sessionId': PropertySchema(
      id: 2,
      name: r'sessionId',
      type: IsarType.string,
    ),
    r'sessionIndex': PropertySchema(
      id: 3,
      name: r'sessionIndex',
      type: IsarType.long,
    ),
    r'updatedAt': PropertySchema(
      id: 4,
      name: r'updatedAt',
      type: IsarType.long,
    )
  },
  estimateSize: _chatSessionCollectionEstimateSize,
  serialize: _chatSessionCollectionSerialize,
  deserialize: _chatSessionCollectionDeserialize,
  deserializeProp: _chatSessionCollectionDeserializeProp,
  idName: r'id',
  indexes: {
    r'sessionId': IndexSchema(
      id: 6949518585047923839,
      name: r'sessionId',
      unique: true,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'sessionId',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _chatSessionCollectionGetId,
  getLinks: _chatSessionCollectionGetLinks,
  attach: _chatSessionCollectionAttach,
  version: '3.1.0+1',
);

int _chatSessionCollectionEstimateSize(
  ChatSessionCollection object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.characterId.length * 3;
  bytesCount += 3 + object.messagesJson.length * 3;
  bytesCount += 3 + object.sessionId.length * 3;
  return bytesCount;
}

void _chatSessionCollectionSerialize(
  ChatSessionCollection object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.characterId);
  writer.writeString(offsets[1], object.messagesJson);
  writer.writeString(offsets[2], object.sessionId);
  writer.writeLong(offsets[3], object.sessionIndex);
  writer.writeLong(offsets[4], object.updatedAt);
}

ChatSessionCollection _chatSessionCollectionDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = ChatSessionCollection();
  object.characterId = reader.readString(offsets[0]);
  object.id = id;
  object.messagesJson = reader.readString(offsets[1]);
  object.sessionId = reader.readString(offsets[2]);
  object.sessionIndex = reader.readLong(offsets[3]);
  object.updatedAt = reader.readLong(offsets[4]);
  return object;
}

P _chatSessionCollectionDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readString(offset)) as P;
    case 1:
      return (reader.readString(offset)) as P;
    case 2:
      return (reader.readString(offset)) as P;
    case 3:
      return (reader.readLong(offset)) as P;
    case 4:
      return (reader.readLong(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _chatSessionCollectionGetId(ChatSessionCollection object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _chatSessionCollectionGetLinks(
    ChatSessionCollection object) {
  return [];
}

void _chatSessionCollectionAttach(
    IsarCollection<dynamic> col, Id id, ChatSessionCollection object) {
  object.id = id;
}

extension ChatSessionCollectionByIndex
    on IsarCollection<ChatSessionCollection> {
  Future<ChatSessionCollection?> getBySessionId(String sessionId) {
    return getByIndex(r'sessionId', [sessionId]);
  }

  ChatSessionCollection? getBySessionIdSync(String sessionId) {
    return getByIndexSync(r'sessionId', [sessionId]);
  }

  Future<bool> deleteBySessionId(String sessionId) {
    return deleteByIndex(r'sessionId', [sessionId]);
  }

  bool deleteBySessionIdSync(String sessionId) {
    return deleteByIndexSync(r'sessionId', [sessionId]);
  }

  Future<List<ChatSessionCollection?>> getAllBySessionId(
      List<String> sessionIdValues) {
    final values = sessionIdValues.map((e) => [e]).toList();
    return getAllByIndex(r'sessionId', values);
  }

  List<ChatSessionCollection?> getAllBySessionIdSync(
      List<String> sessionIdValues) {
    final values = sessionIdValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'sessionId', values);
  }

  Future<int> deleteAllBySessionId(List<String> sessionIdValues) {
    final values = sessionIdValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'sessionId', values);
  }

  int deleteAllBySessionIdSync(List<String> sessionIdValues) {
    final values = sessionIdValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'sessionId', values);
  }

  Future<Id> putBySessionId(ChatSessionCollection object) {
    return putByIndex(r'sessionId', object);
  }

  Id putBySessionIdSync(ChatSessionCollection object, {bool saveLinks = true}) {
    return putByIndexSync(r'sessionId', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllBySessionId(List<ChatSessionCollection> objects) {
    return putAllByIndex(r'sessionId', objects);
  }

  List<Id> putAllBySessionIdSync(List<ChatSessionCollection> objects,
      {bool saveLinks = true}) {
    return putAllByIndexSync(r'sessionId', objects, saveLinks: saveLinks);
  }
}

extension ChatSessionCollectionQueryWhereSort
    on QueryBuilder<ChatSessionCollection, ChatSessionCollection, QWhere> {
  QueryBuilder<ChatSessionCollection, ChatSessionCollection, QAfterWhere>
      anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension ChatSessionCollectionQueryWhere on QueryBuilder<ChatSessionCollection,
    ChatSessionCollection, QWhereClause> {
  QueryBuilder<ChatSessionCollection, ChatSessionCollection, QAfterWhereClause>
      idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection, QAfterWhereClause>
      idNotEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection, QAfterWhereClause>
      idGreaterThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection, QAfterWhereClause>
      idLessThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection, QAfterWhereClause>
      idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: lowerId,
        includeLower: includeLower,
        upper: upperId,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection, QAfterWhereClause>
      sessionIdEqualTo(String sessionId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'sessionId',
        value: [sessionId],
      ));
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection, QAfterWhereClause>
      sessionIdNotEqualTo(String sessionId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'sessionId',
              lower: [],
              upper: [sessionId],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'sessionId',
              lower: [sessionId],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'sessionId',
              lower: [sessionId],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'sessionId',
              lower: [],
              upper: [sessionId],
              includeUpper: false,
            ));
      }
    });
  }
}

extension ChatSessionCollectionQueryFilter on QueryBuilder<
    ChatSessionCollection, ChatSessionCollection, QFilterCondition> {
  QueryBuilder<ChatSessionCollection, ChatSessionCollection,
      QAfterFilterCondition> characterIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'characterId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection,
      QAfterFilterCondition> characterIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'characterId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection,
      QAfterFilterCondition> characterIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'characterId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection,
      QAfterFilterCondition> characterIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'characterId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection,
      QAfterFilterCondition> characterIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'characterId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection,
      QAfterFilterCondition> characterIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'characterId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection,
          QAfterFilterCondition>
      characterIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'characterId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection,
          QAfterFilterCondition>
      characterIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'characterId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection,
      QAfterFilterCondition> characterIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'characterId',
        value: '',
      ));
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection,
      QAfterFilterCondition> characterIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'characterId',
        value: '',
      ));
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection,
      QAfterFilterCondition> idEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection,
      QAfterFilterCondition> idGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection,
      QAfterFilterCondition> idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection,
      QAfterFilterCondition> idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'id',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection,
      QAfterFilterCondition> messagesJsonEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'messagesJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection,
      QAfterFilterCondition> messagesJsonGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'messagesJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection,
      QAfterFilterCondition> messagesJsonLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'messagesJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection,
      QAfterFilterCondition> messagesJsonBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'messagesJson',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection,
      QAfterFilterCondition> messagesJsonStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'messagesJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection,
      QAfterFilterCondition> messagesJsonEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'messagesJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection,
          QAfterFilterCondition>
      messagesJsonContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'messagesJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection,
          QAfterFilterCondition>
      messagesJsonMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'messagesJson',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection,
      QAfterFilterCondition> messagesJsonIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'messagesJson',
        value: '',
      ));
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection,
      QAfterFilterCondition> messagesJsonIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'messagesJson',
        value: '',
      ));
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection,
      QAfterFilterCondition> sessionIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'sessionId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection,
      QAfterFilterCondition> sessionIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'sessionId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection,
      QAfterFilterCondition> sessionIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'sessionId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection,
      QAfterFilterCondition> sessionIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'sessionId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection,
      QAfterFilterCondition> sessionIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'sessionId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection,
      QAfterFilterCondition> sessionIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'sessionId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection,
          QAfterFilterCondition>
      sessionIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'sessionId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection,
          QAfterFilterCondition>
      sessionIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'sessionId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection,
      QAfterFilterCondition> sessionIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'sessionId',
        value: '',
      ));
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection,
      QAfterFilterCondition> sessionIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'sessionId',
        value: '',
      ));
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection,
      QAfterFilterCondition> sessionIndexEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'sessionIndex',
        value: value,
      ));
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection,
      QAfterFilterCondition> sessionIndexGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'sessionIndex',
        value: value,
      ));
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection,
      QAfterFilterCondition> sessionIndexLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'sessionIndex',
        value: value,
      ));
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection,
      QAfterFilterCondition> sessionIndexBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'sessionIndex',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection,
      QAfterFilterCondition> updatedAtEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'updatedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection,
      QAfterFilterCondition> updatedAtGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'updatedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection,
      QAfterFilterCondition> updatedAtLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'updatedAt',
        value: value,
      ));
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection,
      QAfterFilterCondition> updatedAtBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'updatedAt',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }
}

extension ChatSessionCollectionQueryObject on QueryBuilder<
    ChatSessionCollection, ChatSessionCollection, QFilterCondition> {}

extension ChatSessionCollectionQueryLinks on QueryBuilder<ChatSessionCollection,
    ChatSessionCollection, QFilterCondition> {}

extension ChatSessionCollectionQuerySortBy
    on QueryBuilder<ChatSessionCollection, ChatSessionCollection, QSortBy> {
  QueryBuilder<ChatSessionCollection, ChatSessionCollection, QAfterSortBy>
      sortByCharacterId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'characterId', Sort.asc);
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection, QAfterSortBy>
      sortByCharacterIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'characterId', Sort.desc);
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection, QAfterSortBy>
      sortByMessagesJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'messagesJson', Sort.asc);
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection, QAfterSortBy>
      sortByMessagesJsonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'messagesJson', Sort.desc);
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection, QAfterSortBy>
      sortBySessionId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sessionId', Sort.asc);
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection, QAfterSortBy>
      sortBySessionIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sessionId', Sort.desc);
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection, QAfterSortBy>
      sortBySessionIndex() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sessionIndex', Sort.asc);
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection, QAfterSortBy>
      sortBySessionIndexDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sessionIndex', Sort.desc);
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection, QAfterSortBy>
      sortByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection, QAfterSortBy>
      sortByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }
}

extension ChatSessionCollectionQuerySortThenBy
    on QueryBuilder<ChatSessionCollection, ChatSessionCollection, QSortThenBy> {
  QueryBuilder<ChatSessionCollection, ChatSessionCollection, QAfterSortBy>
      thenByCharacterId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'characterId', Sort.asc);
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection, QAfterSortBy>
      thenByCharacterIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'characterId', Sort.desc);
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection, QAfterSortBy>
      thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection, QAfterSortBy>
      thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection, QAfterSortBy>
      thenByMessagesJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'messagesJson', Sort.asc);
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection, QAfterSortBy>
      thenByMessagesJsonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'messagesJson', Sort.desc);
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection, QAfterSortBy>
      thenBySessionId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sessionId', Sort.asc);
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection, QAfterSortBy>
      thenBySessionIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sessionId', Sort.desc);
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection, QAfterSortBy>
      thenBySessionIndex() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sessionIndex', Sort.asc);
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection, QAfterSortBy>
      thenBySessionIndexDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sessionIndex', Sort.desc);
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection, QAfterSortBy>
      thenByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection, QAfterSortBy>
      thenByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }
}

extension ChatSessionCollectionQueryWhereDistinct
    on QueryBuilder<ChatSessionCollection, ChatSessionCollection, QDistinct> {
  QueryBuilder<ChatSessionCollection, ChatSessionCollection, QDistinct>
      distinctByCharacterId({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'characterId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection, QDistinct>
      distinctByMessagesJson({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'messagesJson', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection, QDistinct>
      distinctBySessionId({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'sessionId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection, QDistinct>
      distinctBySessionIndex() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'sessionIndex');
    });
  }

  QueryBuilder<ChatSessionCollection, ChatSessionCollection, QDistinct>
      distinctByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'updatedAt');
    });
  }
}

extension ChatSessionCollectionQueryProperty on QueryBuilder<
    ChatSessionCollection, ChatSessionCollection, QQueryProperty> {
  QueryBuilder<ChatSessionCollection, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<ChatSessionCollection, String, QQueryOperations>
      characterIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'characterId');
    });
  }

  QueryBuilder<ChatSessionCollection, String, QQueryOperations>
      messagesJsonProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'messagesJson');
    });
  }

  QueryBuilder<ChatSessionCollection, String, QQueryOperations>
      sessionIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'sessionId');
    });
  }

  QueryBuilder<ChatSessionCollection, int, QQueryOperations>
      sessionIndexProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'sessionIndex');
    });
  }

  QueryBuilder<ChatSessionCollection, int, QQueryOperations>
      updatedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'updatedAt');
    });
  }
}

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetPresetCollectionCollection on Isar {
  IsarCollection<PresetCollection> get presetCollections => this.collection();
}

const PresetCollectionSchema = CollectionSchema(
  name: r'PresetCollection',
  id: 6576788312337613660,
  properties: {
    r'dataJson': PropertySchema(
      id: 0,
      name: r'dataJson',
      type: IsarType.string,
    ),
    r'name': PropertySchema(
      id: 1,
      name: r'name',
      type: IsarType.string,
    ),
    r'presetId': PropertySchema(
      id: 2,
      name: r'presetId',
      type: IsarType.string,
    )
  },
  estimateSize: _presetCollectionEstimateSize,
  serialize: _presetCollectionSerialize,
  deserialize: _presetCollectionDeserialize,
  deserializeProp: _presetCollectionDeserializeProp,
  idName: r'id',
  indexes: {
    r'presetId': IndexSchema(
      id: -2454531593692408596,
      name: r'presetId',
      unique: true,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'presetId',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _presetCollectionGetId,
  getLinks: _presetCollectionGetLinks,
  attach: _presetCollectionAttach,
  version: '3.1.0+1',
);

int _presetCollectionEstimateSize(
  PresetCollection object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.dataJson.length * 3;
  bytesCount += 3 + object.name.length * 3;
  bytesCount += 3 + object.presetId.length * 3;
  return bytesCount;
}

void _presetCollectionSerialize(
  PresetCollection object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.dataJson);
  writer.writeString(offsets[1], object.name);
  writer.writeString(offsets[2], object.presetId);
}

PresetCollection _presetCollectionDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = PresetCollection();
  object.dataJson = reader.readString(offsets[0]);
  object.id = id;
  object.name = reader.readString(offsets[1]);
  object.presetId = reader.readString(offsets[2]);
  return object;
}

P _presetCollectionDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readString(offset)) as P;
    case 1:
      return (reader.readString(offset)) as P;
    case 2:
      return (reader.readString(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _presetCollectionGetId(PresetCollection object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _presetCollectionGetLinks(PresetCollection object) {
  return [];
}

void _presetCollectionAttach(
    IsarCollection<dynamic> col, Id id, PresetCollection object) {
  object.id = id;
}

extension PresetCollectionByIndex on IsarCollection<PresetCollection> {
  Future<PresetCollection?> getByPresetId(String presetId) {
    return getByIndex(r'presetId', [presetId]);
  }

  PresetCollection? getByPresetIdSync(String presetId) {
    return getByIndexSync(r'presetId', [presetId]);
  }

  Future<bool> deleteByPresetId(String presetId) {
    return deleteByIndex(r'presetId', [presetId]);
  }

  bool deleteByPresetIdSync(String presetId) {
    return deleteByIndexSync(r'presetId', [presetId]);
  }

  Future<List<PresetCollection?>> getAllByPresetId(
      List<String> presetIdValues) {
    final values = presetIdValues.map((e) => [e]).toList();
    return getAllByIndex(r'presetId', values);
  }

  List<PresetCollection?> getAllByPresetIdSync(List<String> presetIdValues) {
    final values = presetIdValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'presetId', values);
  }

  Future<int> deleteAllByPresetId(List<String> presetIdValues) {
    final values = presetIdValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'presetId', values);
  }

  int deleteAllByPresetIdSync(List<String> presetIdValues) {
    final values = presetIdValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'presetId', values);
  }

  Future<Id> putByPresetId(PresetCollection object) {
    return putByIndex(r'presetId', object);
  }

  Id putByPresetIdSync(PresetCollection object, {bool saveLinks = true}) {
    return putByIndexSync(r'presetId', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByPresetId(List<PresetCollection> objects) {
    return putAllByIndex(r'presetId', objects);
  }

  List<Id> putAllByPresetIdSync(List<PresetCollection> objects,
      {bool saveLinks = true}) {
    return putAllByIndexSync(r'presetId', objects, saveLinks: saveLinks);
  }
}

extension PresetCollectionQueryWhereSort
    on QueryBuilder<PresetCollection, PresetCollection, QWhere> {
  QueryBuilder<PresetCollection, PresetCollection, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension PresetCollectionQueryWhere
    on QueryBuilder<PresetCollection, PresetCollection, QWhereClause> {
  QueryBuilder<PresetCollection, PresetCollection, QAfterWhereClause> idEqualTo(
      Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<PresetCollection, PresetCollection, QAfterWhereClause>
      idNotEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<PresetCollection, PresetCollection, QAfterWhereClause>
      idGreaterThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<PresetCollection, PresetCollection, QAfterWhereClause>
      idLessThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<PresetCollection, PresetCollection, QAfterWhereClause> idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: lowerId,
        includeLower: includeLower,
        upper: upperId,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<PresetCollection, PresetCollection, QAfterWhereClause>
      presetIdEqualTo(String presetId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'presetId',
        value: [presetId],
      ));
    });
  }

  QueryBuilder<PresetCollection, PresetCollection, QAfterWhereClause>
      presetIdNotEqualTo(String presetId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'presetId',
              lower: [],
              upper: [presetId],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'presetId',
              lower: [presetId],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'presetId',
              lower: [presetId],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'presetId',
              lower: [],
              upper: [presetId],
              includeUpper: false,
            ));
      }
    });
  }
}

extension PresetCollectionQueryFilter
    on QueryBuilder<PresetCollection, PresetCollection, QFilterCondition> {
  QueryBuilder<PresetCollection, PresetCollection, QAfterFilterCondition>
      dataJsonEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'dataJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PresetCollection, PresetCollection, QAfterFilterCondition>
      dataJsonGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'dataJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PresetCollection, PresetCollection, QAfterFilterCondition>
      dataJsonLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'dataJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PresetCollection, PresetCollection, QAfterFilterCondition>
      dataJsonBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'dataJson',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PresetCollection, PresetCollection, QAfterFilterCondition>
      dataJsonStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'dataJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PresetCollection, PresetCollection, QAfterFilterCondition>
      dataJsonEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'dataJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PresetCollection, PresetCollection, QAfterFilterCondition>
      dataJsonContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'dataJson',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PresetCollection, PresetCollection, QAfterFilterCondition>
      dataJsonMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'dataJson',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PresetCollection, PresetCollection, QAfterFilterCondition>
      dataJsonIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'dataJson',
        value: '',
      ));
    });
  }

  QueryBuilder<PresetCollection, PresetCollection, QAfterFilterCondition>
      dataJsonIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'dataJson',
        value: '',
      ));
    });
  }

  QueryBuilder<PresetCollection, PresetCollection, QAfterFilterCondition>
      idEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<PresetCollection, PresetCollection, QAfterFilterCondition>
      idGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<PresetCollection, PresetCollection, QAfterFilterCondition>
      idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<PresetCollection, PresetCollection, QAfterFilterCondition>
      idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'id',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<PresetCollection, PresetCollection, QAfterFilterCondition>
      nameEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PresetCollection, PresetCollection, QAfterFilterCondition>
      nameGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PresetCollection, PresetCollection, QAfterFilterCondition>
      nameLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PresetCollection, PresetCollection, QAfterFilterCondition>
      nameBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'name',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PresetCollection, PresetCollection, QAfterFilterCondition>
      nameStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PresetCollection, PresetCollection, QAfterFilterCondition>
      nameEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PresetCollection, PresetCollection, QAfterFilterCondition>
      nameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PresetCollection, PresetCollection, QAfterFilterCondition>
      nameMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'name',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PresetCollection, PresetCollection, QAfterFilterCondition>
      nameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'name',
        value: '',
      ));
    });
  }

  QueryBuilder<PresetCollection, PresetCollection, QAfterFilterCondition>
      nameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'name',
        value: '',
      ));
    });
  }

  QueryBuilder<PresetCollection, PresetCollection, QAfterFilterCondition>
      presetIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'presetId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PresetCollection, PresetCollection, QAfterFilterCondition>
      presetIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'presetId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PresetCollection, PresetCollection, QAfterFilterCondition>
      presetIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'presetId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PresetCollection, PresetCollection, QAfterFilterCondition>
      presetIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'presetId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PresetCollection, PresetCollection, QAfterFilterCondition>
      presetIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'presetId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PresetCollection, PresetCollection, QAfterFilterCondition>
      presetIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'presetId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PresetCollection, PresetCollection, QAfterFilterCondition>
      presetIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'presetId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PresetCollection, PresetCollection, QAfterFilterCondition>
      presetIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'presetId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PresetCollection, PresetCollection, QAfterFilterCondition>
      presetIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'presetId',
        value: '',
      ));
    });
  }

  QueryBuilder<PresetCollection, PresetCollection, QAfterFilterCondition>
      presetIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'presetId',
        value: '',
      ));
    });
  }
}

extension PresetCollectionQueryObject
    on QueryBuilder<PresetCollection, PresetCollection, QFilterCondition> {}

extension PresetCollectionQueryLinks
    on QueryBuilder<PresetCollection, PresetCollection, QFilterCondition> {}

extension PresetCollectionQuerySortBy
    on QueryBuilder<PresetCollection, PresetCollection, QSortBy> {
  QueryBuilder<PresetCollection, PresetCollection, QAfterSortBy>
      sortByDataJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'dataJson', Sort.asc);
    });
  }

  QueryBuilder<PresetCollection, PresetCollection, QAfterSortBy>
      sortByDataJsonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'dataJson', Sort.desc);
    });
  }

  QueryBuilder<PresetCollection, PresetCollection, QAfterSortBy> sortByName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.asc);
    });
  }

  QueryBuilder<PresetCollection, PresetCollection, QAfterSortBy>
      sortByNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.desc);
    });
  }

  QueryBuilder<PresetCollection, PresetCollection, QAfterSortBy>
      sortByPresetId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'presetId', Sort.asc);
    });
  }

  QueryBuilder<PresetCollection, PresetCollection, QAfterSortBy>
      sortByPresetIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'presetId', Sort.desc);
    });
  }
}

extension PresetCollectionQuerySortThenBy
    on QueryBuilder<PresetCollection, PresetCollection, QSortThenBy> {
  QueryBuilder<PresetCollection, PresetCollection, QAfterSortBy>
      thenByDataJson() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'dataJson', Sort.asc);
    });
  }

  QueryBuilder<PresetCollection, PresetCollection, QAfterSortBy>
      thenByDataJsonDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'dataJson', Sort.desc);
    });
  }

  QueryBuilder<PresetCollection, PresetCollection, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<PresetCollection, PresetCollection, QAfterSortBy>
      thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<PresetCollection, PresetCollection, QAfterSortBy> thenByName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.asc);
    });
  }

  QueryBuilder<PresetCollection, PresetCollection, QAfterSortBy>
      thenByNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.desc);
    });
  }

  QueryBuilder<PresetCollection, PresetCollection, QAfterSortBy>
      thenByPresetId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'presetId', Sort.asc);
    });
  }

  QueryBuilder<PresetCollection, PresetCollection, QAfterSortBy>
      thenByPresetIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'presetId', Sort.desc);
    });
  }
}

extension PresetCollectionQueryWhereDistinct
    on QueryBuilder<PresetCollection, PresetCollection, QDistinct> {
  QueryBuilder<PresetCollection, PresetCollection, QDistinct>
      distinctByDataJson({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'dataJson', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<PresetCollection, PresetCollection, QDistinct> distinctByName(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'name', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<PresetCollection, PresetCollection, QDistinct>
      distinctByPresetId({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'presetId', caseSensitive: caseSensitive);
    });
  }
}

extension PresetCollectionQueryProperty
    on QueryBuilder<PresetCollection, PresetCollection, QQueryProperty> {
  QueryBuilder<PresetCollection, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<PresetCollection, String, QQueryOperations> dataJsonProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'dataJson');
    });
  }

  QueryBuilder<PresetCollection, String, QQueryOperations> nameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'name');
    });
  }

  QueryBuilder<PresetCollection, String, QQueryOperations> presetIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'presetId');
    });
  }
}

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetApiConfigCollectionCollection on Isar {
  IsarCollection<ApiConfigCollection> get apiConfigCollections =>
      this.collection();
}

const ApiConfigCollectionSchema = CollectionSchema(
  name: r'ApiConfigCollection',
  id: -1665100789764220467,
  properties: {
    r'apiKey': PropertySchema(
      id: 0,
      name: r'apiKey',
      type: IsarType.string,
    ),
    r'configId': PropertySchema(
      id: 1,
      name: r'configId',
      type: IsarType.string,
    ),
    r'contextSize': PropertySchema(
      id: 2,
      name: r'contextSize',
      type: IsarType.long,
    ),
    r'endpoint': PropertySchema(
      id: 3,
      name: r'endpoint',
      type: IsarType.string,
    ),
    r'maxTokens': PropertySchema(
      id: 4,
      name: r'maxTokens',
      type: IsarType.long,
    ),
    r'model': PropertySchema(
      id: 5,
      name: r'model',
      type: IsarType.string,
    ),
    r'name': PropertySchema(
      id: 6,
      name: r'name',
      type: IsarType.string,
    ),
    r'providerId': PropertySchema(
      id: 7,
      name: r'providerId',
      type: IsarType.string,
    ),
    r'reasoningEffort': PropertySchema(
      id: 8,
      name: r'reasoningEffort',
      type: IsarType.string,
    ),
    r'reasoningTagEnd': PropertySchema(
      id: 9,
      name: r'reasoningTagEnd',
      type: IsarType.string,
    ),
    r'reasoningTagStart': PropertySchema(
      id: 10,
      name: r'reasoningTagStart',
      type: IsarType.string,
    ),
    r'requestReasoning': PropertySchema(
      id: 11,
      name: r'requestReasoning',
      type: IsarType.bool,
    ),
    r'stream': PropertySchema(
      id: 12,
      name: r'stream',
      type: IsarType.bool,
    ),
    r'temperature': PropertySchema(
      id: 13,
      name: r'temperature',
      type: IsarType.double,
    ),
    r'topP': PropertySchema(
      id: 14,
      name: r'topP',
      type: IsarType.double,
    )
  },
  estimateSize: _apiConfigCollectionEstimateSize,
  serialize: _apiConfigCollectionSerialize,
  deserialize: _apiConfigCollectionDeserialize,
  deserializeProp: _apiConfigCollectionDeserializeProp,
  idName: r'id',
  indexes: {
    r'configId': IndexSchema(
      id: 7164334513802924883,
      name: r'configId',
      unique: true,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'configId',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _apiConfigCollectionGetId,
  getLinks: _apiConfigCollectionGetLinks,
  attach: _apiConfigCollectionAttach,
  version: '3.1.0+1',
);

int _apiConfigCollectionEstimateSize(
  ApiConfigCollection object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  {
    final value = object.apiKey;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.configId.length * 3;
  {
    final value = object.endpoint;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.model;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.name.length * 3;
  bytesCount += 3 + object.providerId.length * 3;
  {
    final value = object.reasoningEffort;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.reasoningTagEnd;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.reasoningTagStart;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  return bytesCount;
}

void _apiConfigCollectionSerialize(
  ApiConfigCollection object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.apiKey);
  writer.writeString(offsets[1], object.configId);
  writer.writeLong(offsets[2], object.contextSize);
  writer.writeString(offsets[3], object.endpoint);
  writer.writeLong(offsets[4], object.maxTokens);
  writer.writeString(offsets[5], object.model);
  writer.writeString(offsets[6], object.name);
  writer.writeString(offsets[7], object.providerId);
  writer.writeString(offsets[8], object.reasoningEffort);
  writer.writeString(offsets[9], object.reasoningTagEnd);
  writer.writeString(offsets[10], object.reasoningTagStart);
  writer.writeBool(offsets[11], object.requestReasoning);
  writer.writeBool(offsets[12], object.stream);
  writer.writeDouble(offsets[13], object.temperature);
  writer.writeDouble(offsets[14], object.topP);
}

ApiConfigCollection _apiConfigCollectionDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = ApiConfigCollection();
  object.apiKey = reader.readStringOrNull(offsets[0]);
  object.configId = reader.readString(offsets[1]);
  object.contextSize = reader.readLong(offsets[2]);
  object.endpoint = reader.readStringOrNull(offsets[3]);
  object.id = id;
  object.maxTokens = reader.readLong(offsets[4]);
  object.model = reader.readStringOrNull(offsets[5]);
  object.name = reader.readString(offsets[6]);
  object.providerId = reader.readString(offsets[7]);
  object.reasoningEffort = reader.readStringOrNull(offsets[8]);
  object.reasoningTagEnd = reader.readStringOrNull(offsets[9]);
  object.reasoningTagStart = reader.readStringOrNull(offsets[10]);
  object.requestReasoning = reader.readBool(offsets[11]);
  object.stream = reader.readBool(offsets[12]);
  object.temperature = reader.readDouble(offsets[13]);
  object.topP = reader.readDouble(offsets[14]);
  return object;
}

P _apiConfigCollectionDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readStringOrNull(offset)) as P;
    case 1:
      return (reader.readString(offset)) as P;
    case 2:
      return (reader.readLong(offset)) as P;
    case 3:
      return (reader.readStringOrNull(offset)) as P;
    case 4:
      return (reader.readLong(offset)) as P;
    case 5:
      return (reader.readStringOrNull(offset)) as P;
    case 6:
      return (reader.readString(offset)) as P;
    case 7:
      return (reader.readString(offset)) as P;
    case 8:
      return (reader.readStringOrNull(offset)) as P;
    case 9:
      return (reader.readStringOrNull(offset)) as P;
    case 10:
      return (reader.readStringOrNull(offset)) as P;
    case 11:
      return (reader.readBool(offset)) as P;
    case 12:
      return (reader.readBool(offset)) as P;
    case 13:
      return (reader.readDouble(offset)) as P;
    case 14:
      return (reader.readDouble(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _apiConfigCollectionGetId(ApiConfigCollection object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _apiConfigCollectionGetLinks(
    ApiConfigCollection object) {
  return [];
}

void _apiConfigCollectionAttach(
    IsarCollection<dynamic> col, Id id, ApiConfigCollection object) {
  object.id = id;
}

extension ApiConfigCollectionByIndex on IsarCollection<ApiConfigCollection> {
  Future<ApiConfigCollection?> getByConfigId(String configId) {
    return getByIndex(r'configId', [configId]);
  }

  ApiConfigCollection? getByConfigIdSync(String configId) {
    return getByIndexSync(r'configId', [configId]);
  }

  Future<bool> deleteByConfigId(String configId) {
    return deleteByIndex(r'configId', [configId]);
  }

  bool deleteByConfigIdSync(String configId) {
    return deleteByIndexSync(r'configId', [configId]);
  }

  Future<List<ApiConfigCollection?>> getAllByConfigId(
      List<String> configIdValues) {
    final values = configIdValues.map((e) => [e]).toList();
    return getAllByIndex(r'configId', values);
  }

  List<ApiConfigCollection?> getAllByConfigIdSync(List<String> configIdValues) {
    final values = configIdValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'configId', values);
  }

  Future<int> deleteAllByConfigId(List<String> configIdValues) {
    final values = configIdValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'configId', values);
  }

  int deleteAllByConfigIdSync(List<String> configIdValues) {
    final values = configIdValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'configId', values);
  }

  Future<Id> putByConfigId(ApiConfigCollection object) {
    return putByIndex(r'configId', object);
  }

  Id putByConfigIdSync(ApiConfigCollection object, {bool saveLinks = true}) {
    return putByIndexSync(r'configId', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByConfigId(List<ApiConfigCollection> objects) {
    return putAllByIndex(r'configId', objects);
  }

  List<Id> putAllByConfigIdSync(List<ApiConfigCollection> objects,
      {bool saveLinks = true}) {
    return putAllByIndexSync(r'configId', objects, saveLinks: saveLinks);
  }
}

extension ApiConfigCollectionQueryWhereSort
    on QueryBuilder<ApiConfigCollection, ApiConfigCollection, QWhere> {
  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension ApiConfigCollectionQueryWhere
    on QueryBuilder<ApiConfigCollection, ApiConfigCollection, QWhereClause> {
  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterWhereClause>
      idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterWhereClause>
      idNotEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterWhereClause>
      idGreaterThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterWhereClause>
      idLessThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterWhereClause>
      idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: lowerId,
        includeLower: includeLower,
        upper: upperId,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterWhereClause>
      configIdEqualTo(String configId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'configId',
        value: [configId],
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterWhereClause>
      configIdNotEqualTo(String configId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'configId',
              lower: [],
              upper: [configId],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'configId',
              lower: [configId],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'configId',
              lower: [configId],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'configId',
              lower: [],
              upper: [configId],
              includeUpper: false,
            ));
      }
    });
  }
}

extension ApiConfigCollectionQueryFilter on QueryBuilder<ApiConfigCollection,
    ApiConfigCollection, QFilterCondition> {
  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      apiKeyIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'apiKey',
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      apiKeyIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'apiKey',
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      apiKeyEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'apiKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      apiKeyGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'apiKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      apiKeyLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'apiKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      apiKeyBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'apiKey',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      apiKeyStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'apiKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      apiKeyEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'apiKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      apiKeyContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'apiKey',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      apiKeyMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'apiKey',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      apiKeyIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'apiKey',
        value: '',
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      apiKeyIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'apiKey',
        value: '',
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      configIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'configId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      configIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'configId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      configIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'configId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      configIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'configId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      configIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'configId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      configIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'configId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      configIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'configId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      configIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'configId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      configIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'configId',
        value: '',
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      configIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'configId',
        value: '',
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      contextSizeEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'contextSize',
        value: value,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      contextSizeGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'contextSize',
        value: value,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      contextSizeLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'contextSize',
        value: value,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      contextSizeBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'contextSize',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      endpointIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'endpoint',
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      endpointIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'endpoint',
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      endpointEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'endpoint',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      endpointGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'endpoint',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      endpointLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'endpoint',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      endpointBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'endpoint',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      endpointStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'endpoint',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      endpointEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'endpoint',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      endpointContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'endpoint',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      endpointMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'endpoint',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      endpointIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'endpoint',
        value: '',
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      endpointIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'endpoint',
        value: '',
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      idEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      idGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'id',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      maxTokensEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'maxTokens',
        value: value,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      maxTokensGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'maxTokens',
        value: value,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      maxTokensLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'maxTokens',
        value: value,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      maxTokensBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'maxTokens',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      modelIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'model',
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      modelIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'model',
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      modelEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'model',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      modelGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'model',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      modelLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'model',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      modelBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'model',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      modelStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'model',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      modelEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'model',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      modelContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'model',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      modelMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'model',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      modelIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'model',
        value: '',
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      modelIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'model',
        value: '',
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      nameEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      nameGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      nameLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      nameBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'name',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      nameStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      nameEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      nameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      nameMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'name',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      nameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'name',
        value: '',
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      nameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'name',
        value: '',
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      providerIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'providerId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      providerIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'providerId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      providerIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'providerId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      providerIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'providerId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      providerIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'providerId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      providerIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'providerId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      providerIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'providerId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      providerIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'providerId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      providerIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'providerId',
        value: '',
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      providerIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'providerId',
        value: '',
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      reasoningEffortIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'reasoningEffort',
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      reasoningEffortIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'reasoningEffort',
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      reasoningEffortEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'reasoningEffort',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      reasoningEffortGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'reasoningEffort',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      reasoningEffortLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'reasoningEffort',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      reasoningEffortBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'reasoningEffort',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      reasoningEffortStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'reasoningEffort',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      reasoningEffortEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'reasoningEffort',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      reasoningEffortContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'reasoningEffort',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      reasoningEffortMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'reasoningEffort',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      reasoningEffortIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'reasoningEffort',
        value: '',
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      reasoningEffortIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'reasoningEffort',
        value: '',
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      reasoningTagEndIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'reasoningTagEnd',
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      reasoningTagEndIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'reasoningTagEnd',
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      reasoningTagEndEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'reasoningTagEnd',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      reasoningTagEndGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'reasoningTagEnd',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      reasoningTagEndLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'reasoningTagEnd',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      reasoningTagEndBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'reasoningTagEnd',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      reasoningTagEndStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'reasoningTagEnd',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      reasoningTagEndEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'reasoningTagEnd',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      reasoningTagEndContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'reasoningTagEnd',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      reasoningTagEndMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'reasoningTagEnd',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      reasoningTagEndIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'reasoningTagEnd',
        value: '',
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      reasoningTagEndIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'reasoningTagEnd',
        value: '',
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      reasoningTagStartIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'reasoningTagStart',
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      reasoningTagStartIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'reasoningTagStart',
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      reasoningTagStartEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'reasoningTagStart',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      reasoningTagStartGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'reasoningTagStart',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      reasoningTagStartLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'reasoningTagStart',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      reasoningTagStartBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'reasoningTagStart',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      reasoningTagStartStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'reasoningTagStart',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      reasoningTagStartEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'reasoningTagStart',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      reasoningTagStartContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'reasoningTagStart',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      reasoningTagStartMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'reasoningTagStart',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      reasoningTagStartIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'reasoningTagStart',
        value: '',
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      reasoningTagStartIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'reasoningTagStart',
        value: '',
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      requestReasoningEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'requestReasoning',
        value: value,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      streamEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'stream',
        value: value,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      temperatureEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'temperature',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      temperatureGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'temperature',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      temperatureLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'temperature',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      temperatureBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'temperature',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      topPEqualTo(
    double value, {
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'topP',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      topPGreaterThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'topP',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      topPLessThan(
    double value, {
    bool include = false,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'topP',
        value: value,
        epsilon: epsilon,
      ));
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterFilterCondition>
      topPBetween(
    double lower,
    double upper, {
    bool includeLower = true,
    bool includeUpper = true,
    double epsilon = Query.epsilon,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'topP',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        epsilon: epsilon,
      ));
    });
  }
}

extension ApiConfigCollectionQueryObject on QueryBuilder<ApiConfigCollection,
    ApiConfigCollection, QFilterCondition> {}

extension ApiConfigCollectionQueryLinks on QueryBuilder<ApiConfigCollection,
    ApiConfigCollection, QFilterCondition> {}

extension ApiConfigCollectionQuerySortBy
    on QueryBuilder<ApiConfigCollection, ApiConfigCollection, QSortBy> {
  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterSortBy>
      sortByApiKey() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'apiKey', Sort.asc);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterSortBy>
      sortByApiKeyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'apiKey', Sort.desc);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterSortBy>
      sortByConfigId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'configId', Sort.asc);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterSortBy>
      sortByConfigIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'configId', Sort.desc);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterSortBy>
      sortByContextSize() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'contextSize', Sort.asc);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterSortBy>
      sortByContextSizeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'contextSize', Sort.desc);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterSortBy>
      sortByEndpoint() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'endpoint', Sort.asc);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterSortBy>
      sortByEndpointDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'endpoint', Sort.desc);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterSortBy>
      sortByMaxTokens() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'maxTokens', Sort.asc);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterSortBy>
      sortByMaxTokensDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'maxTokens', Sort.desc);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterSortBy>
      sortByModel() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'model', Sort.asc);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterSortBy>
      sortByModelDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'model', Sort.desc);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterSortBy>
      sortByName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.asc);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterSortBy>
      sortByNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.desc);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterSortBy>
      sortByProviderId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'providerId', Sort.asc);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterSortBy>
      sortByProviderIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'providerId', Sort.desc);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterSortBy>
      sortByReasoningEffort() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'reasoningEffort', Sort.asc);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterSortBy>
      sortByReasoningEffortDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'reasoningEffort', Sort.desc);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterSortBy>
      sortByReasoningTagEnd() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'reasoningTagEnd', Sort.asc);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterSortBy>
      sortByReasoningTagEndDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'reasoningTagEnd', Sort.desc);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterSortBy>
      sortByReasoningTagStart() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'reasoningTagStart', Sort.asc);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterSortBy>
      sortByReasoningTagStartDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'reasoningTagStart', Sort.desc);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterSortBy>
      sortByRequestReasoning() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'requestReasoning', Sort.asc);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterSortBy>
      sortByRequestReasoningDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'requestReasoning', Sort.desc);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterSortBy>
      sortByStream() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'stream', Sort.asc);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterSortBy>
      sortByStreamDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'stream', Sort.desc);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterSortBy>
      sortByTemperature() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'temperature', Sort.asc);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterSortBy>
      sortByTemperatureDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'temperature', Sort.desc);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterSortBy>
      sortByTopP() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'topP', Sort.asc);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterSortBy>
      sortByTopPDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'topP', Sort.desc);
    });
  }
}

extension ApiConfigCollectionQuerySortThenBy
    on QueryBuilder<ApiConfigCollection, ApiConfigCollection, QSortThenBy> {
  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterSortBy>
      thenByApiKey() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'apiKey', Sort.asc);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterSortBy>
      thenByApiKeyDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'apiKey', Sort.desc);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterSortBy>
      thenByConfigId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'configId', Sort.asc);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterSortBy>
      thenByConfigIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'configId', Sort.desc);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterSortBy>
      thenByContextSize() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'contextSize', Sort.asc);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterSortBy>
      thenByContextSizeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'contextSize', Sort.desc);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterSortBy>
      thenByEndpoint() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'endpoint', Sort.asc);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterSortBy>
      thenByEndpointDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'endpoint', Sort.desc);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterSortBy>
      thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterSortBy>
      thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterSortBy>
      thenByMaxTokens() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'maxTokens', Sort.asc);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterSortBy>
      thenByMaxTokensDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'maxTokens', Sort.desc);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterSortBy>
      thenByModel() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'model', Sort.asc);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterSortBy>
      thenByModelDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'model', Sort.desc);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterSortBy>
      thenByName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.asc);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterSortBy>
      thenByNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.desc);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterSortBy>
      thenByProviderId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'providerId', Sort.asc);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterSortBy>
      thenByProviderIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'providerId', Sort.desc);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterSortBy>
      thenByReasoningEffort() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'reasoningEffort', Sort.asc);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterSortBy>
      thenByReasoningEffortDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'reasoningEffort', Sort.desc);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterSortBy>
      thenByReasoningTagEnd() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'reasoningTagEnd', Sort.asc);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterSortBy>
      thenByReasoningTagEndDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'reasoningTagEnd', Sort.desc);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterSortBy>
      thenByReasoningTagStart() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'reasoningTagStart', Sort.asc);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterSortBy>
      thenByReasoningTagStartDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'reasoningTagStart', Sort.desc);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterSortBy>
      thenByRequestReasoning() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'requestReasoning', Sort.asc);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterSortBy>
      thenByRequestReasoningDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'requestReasoning', Sort.desc);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterSortBy>
      thenByStream() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'stream', Sort.asc);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterSortBy>
      thenByStreamDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'stream', Sort.desc);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterSortBy>
      thenByTemperature() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'temperature', Sort.asc);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterSortBy>
      thenByTemperatureDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'temperature', Sort.desc);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterSortBy>
      thenByTopP() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'topP', Sort.asc);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QAfterSortBy>
      thenByTopPDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'topP', Sort.desc);
    });
  }
}

extension ApiConfigCollectionQueryWhereDistinct
    on QueryBuilder<ApiConfigCollection, ApiConfigCollection, QDistinct> {
  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QDistinct>
      distinctByApiKey({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'apiKey', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QDistinct>
      distinctByConfigId({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'configId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QDistinct>
      distinctByContextSize() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'contextSize');
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QDistinct>
      distinctByEndpoint({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'endpoint', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QDistinct>
      distinctByMaxTokens() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'maxTokens');
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QDistinct>
      distinctByModel({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'model', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QDistinct>
      distinctByName({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'name', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QDistinct>
      distinctByProviderId({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'providerId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QDistinct>
      distinctByReasoningEffort({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'reasoningEffort',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QDistinct>
      distinctByReasoningTagEnd({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'reasoningTagEnd',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QDistinct>
      distinctByReasoningTagStart({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'reasoningTagStart',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QDistinct>
      distinctByRequestReasoning() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'requestReasoning');
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QDistinct>
      distinctByStream() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'stream');
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QDistinct>
      distinctByTemperature() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'temperature');
    });
  }

  QueryBuilder<ApiConfigCollection, ApiConfigCollection, QDistinct>
      distinctByTopP() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'topP');
    });
  }
}

extension ApiConfigCollectionQueryProperty
    on QueryBuilder<ApiConfigCollection, ApiConfigCollection, QQueryProperty> {
  QueryBuilder<ApiConfigCollection, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<ApiConfigCollection, String?, QQueryOperations>
      apiKeyProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'apiKey');
    });
  }

  QueryBuilder<ApiConfigCollection, String, QQueryOperations>
      configIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'configId');
    });
  }

  QueryBuilder<ApiConfigCollection, int, QQueryOperations>
      contextSizeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'contextSize');
    });
  }

  QueryBuilder<ApiConfigCollection, String?, QQueryOperations>
      endpointProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'endpoint');
    });
  }

  QueryBuilder<ApiConfigCollection, int, QQueryOperations> maxTokensProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'maxTokens');
    });
  }

  QueryBuilder<ApiConfigCollection, String?, QQueryOperations> modelProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'model');
    });
  }

  QueryBuilder<ApiConfigCollection, String, QQueryOperations> nameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'name');
    });
  }

  QueryBuilder<ApiConfigCollection, String, QQueryOperations>
      providerIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'providerId');
    });
  }

  QueryBuilder<ApiConfigCollection, String?, QQueryOperations>
      reasoningEffortProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'reasoningEffort');
    });
  }

  QueryBuilder<ApiConfigCollection, String?, QQueryOperations>
      reasoningTagEndProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'reasoningTagEnd');
    });
  }

  QueryBuilder<ApiConfigCollection, String?, QQueryOperations>
      reasoningTagStartProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'reasoningTagStart');
    });
  }

  QueryBuilder<ApiConfigCollection, bool, QQueryOperations>
      requestReasoningProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'requestReasoning');
    });
  }

  QueryBuilder<ApiConfigCollection, bool, QQueryOperations> streamProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'stream');
    });
  }

  QueryBuilder<ApiConfigCollection, double, QQueryOperations>
      temperatureProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'temperature');
    });
  }

  QueryBuilder<ApiConfigCollection, double, QQueryOperations> topPProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'topP');
    });
  }
}

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetPersonaCollectionCollection on Isar {
  IsarCollection<PersonaCollection> get personaCollections => this.collection();
}

const PersonaCollectionSchema = CollectionSchema(
  name: r'PersonaCollection',
  id: 1758070771714845770,
  properties: {
    r'avatarPath': PropertySchema(
      id: 0,
      name: r'avatarPath',
      type: IsarType.string,
    ),
    r'name': PropertySchema(
      id: 1,
      name: r'name',
      type: IsarType.string,
    ),
    r'personaId': PropertySchema(
      id: 2,
      name: r'personaId',
      type: IsarType.string,
    ),
    r'prompt': PropertySchema(
      id: 3,
      name: r'prompt',
      type: IsarType.string,
    )
  },
  estimateSize: _personaCollectionEstimateSize,
  serialize: _personaCollectionSerialize,
  deserialize: _personaCollectionDeserialize,
  deserializeProp: _personaCollectionDeserializeProp,
  idName: r'id',
  indexes: {
    r'personaId': IndexSchema(
      id: -8614534782526162629,
      name: r'personaId',
      unique: true,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'personaId',
          type: IndexType.hash,
          caseSensitive: true,
        )
      ],
    )
  },
  links: {},
  embeddedSchemas: {},
  getId: _personaCollectionGetId,
  getLinks: _personaCollectionGetLinks,
  attach: _personaCollectionAttach,
  version: '3.1.0+1',
);

int _personaCollectionEstimateSize(
  PersonaCollection object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  {
    final value = object.avatarPath;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.name.length * 3;
  bytesCount += 3 + object.personaId.length * 3;
  {
    final value = object.prompt;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  return bytesCount;
}

void _personaCollectionSerialize(
  PersonaCollection object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.avatarPath);
  writer.writeString(offsets[1], object.name);
  writer.writeString(offsets[2], object.personaId);
  writer.writeString(offsets[3], object.prompt);
}

PersonaCollection _personaCollectionDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = PersonaCollection();
  object.avatarPath = reader.readStringOrNull(offsets[0]);
  object.id = id;
  object.name = reader.readString(offsets[1]);
  object.personaId = reader.readString(offsets[2]);
  object.prompt = reader.readStringOrNull(offsets[3]);
  return object;
}

P _personaCollectionDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readStringOrNull(offset)) as P;
    case 1:
      return (reader.readString(offset)) as P;
    case 2:
      return (reader.readString(offset)) as P;
    case 3:
      return (reader.readStringOrNull(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _personaCollectionGetId(PersonaCollection object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _personaCollectionGetLinks(
    PersonaCollection object) {
  return [];
}

void _personaCollectionAttach(
    IsarCollection<dynamic> col, Id id, PersonaCollection object) {
  object.id = id;
}

extension PersonaCollectionByIndex on IsarCollection<PersonaCollection> {
  Future<PersonaCollection?> getByPersonaId(String personaId) {
    return getByIndex(r'personaId', [personaId]);
  }

  PersonaCollection? getByPersonaIdSync(String personaId) {
    return getByIndexSync(r'personaId', [personaId]);
  }

  Future<bool> deleteByPersonaId(String personaId) {
    return deleteByIndex(r'personaId', [personaId]);
  }

  bool deleteByPersonaIdSync(String personaId) {
    return deleteByIndexSync(r'personaId', [personaId]);
  }

  Future<List<PersonaCollection?>> getAllByPersonaId(
      List<String> personaIdValues) {
    final values = personaIdValues.map((e) => [e]).toList();
    return getAllByIndex(r'personaId', values);
  }

  List<PersonaCollection?> getAllByPersonaIdSync(List<String> personaIdValues) {
    final values = personaIdValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'personaId', values);
  }

  Future<int> deleteAllByPersonaId(List<String> personaIdValues) {
    final values = personaIdValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'personaId', values);
  }

  int deleteAllByPersonaIdSync(List<String> personaIdValues) {
    final values = personaIdValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'personaId', values);
  }

  Future<Id> putByPersonaId(PersonaCollection object) {
    return putByIndex(r'personaId', object);
  }

  Id putByPersonaIdSync(PersonaCollection object, {bool saveLinks = true}) {
    return putByIndexSync(r'personaId', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByPersonaId(List<PersonaCollection> objects) {
    return putAllByIndex(r'personaId', objects);
  }

  List<Id> putAllByPersonaIdSync(List<PersonaCollection> objects,
      {bool saveLinks = true}) {
    return putAllByIndexSync(r'personaId', objects, saveLinks: saveLinks);
  }
}

extension PersonaCollectionQueryWhereSort
    on QueryBuilder<PersonaCollection, PersonaCollection, QWhere> {
  QueryBuilder<PersonaCollection, PersonaCollection, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension PersonaCollectionQueryWhere
    on QueryBuilder<PersonaCollection, PersonaCollection, QWhereClause> {
  QueryBuilder<PersonaCollection, PersonaCollection, QAfterWhereClause>
      idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterWhereClause>
      idNotEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterWhereClause>
      idGreaterThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterWhereClause>
      idLessThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterWhereClause>
      idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: lowerId,
        includeLower: includeLower,
        upper: upperId,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterWhereClause>
      personaIdEqualTo(String personaId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IndexWhereClause.equalTo(
        indexName: r'personaId',
        value: [personaId],
      ));
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterWhereClause>
      personaIdNotEqualTo(String personaId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'personaId',
              lower: [],
              upper: [personaId],
              includeUpper: false,
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'personaId',
              lower: [personaId],
              includeLower: false,
              upper: [],
            ));
      } else {
        return query
            .addWhereClause(IndexWhereClause.between(
              indexName: r'personaId',
              lower: [personaId],
              includeLower: false,
              upper: [],
            ))
            .addWhereClause(IndexWhereClause.between(
              indexName: r'personaId',
              lower: [],
              upper: [personaId],
              includeUpper: false,
            ));
      }
    });
  }
}

extension PersonaCollectionQueryFilter
    on QueryBuilder<PersonaCollection, PersonaCollection, QFilterCondition> {
  QueryBuilder<PersonaCollection, PersonaCollection, QAfterFilterCondition>
      avatarPathIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'avatarPath',
      ));
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterFilterCondition>
      avatarPathIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'avatarPath',
      ));
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterFilterCondition>
      avatarPathEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'avatarPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterFilterCondition>
      avatarPathGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'avatarPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterFilterCondition>
      avatarPathLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'avatarPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterFilterCondition>
      avatarPathBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'avatarPath',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterFilterCondition>
      avatarPathStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'avatarPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterFilterCondition>
      avatarPathEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'avatarPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterFilterCondition>
      avatarPathContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'avatarPath',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterFilterCondition>
      avatarPathMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'avatarPath',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterFilterCondition>
      avatarPathIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'avatarPath',
        value: '',
      ));
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterFilterCondition>
      avatarPathIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'avatarPath',
        value: '',
      ));
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterFilterCondition>
      idEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterFilterCondition>
      idGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterFilterCondition>
      idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterFilterCondition>
      idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'id',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterFilterCondition>
      nameEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterFilterCondition>
      nameGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterFilterCondition>
      nameLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterFilterCondition>
      nameBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'name',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterFilterCondition>
      nameStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterFilterCondition>
      nameEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterFilterCondition>
      nameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'name',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterFilterCondition>
      nameMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'name',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterFilterCondition>
      nameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'name',
        value: '',
      ));
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterFilterCondition>
      nameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'name',
        value: '',
      ));
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterFilterCondition>
      personaIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'personaId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterFilterCondition>
      personaIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'personaId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterFilterCondition>
      personaIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'personaId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterFilterCondition>
      personaIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'personaId',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterFilterCondition>
      personaIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'personaId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterFilterCondition>
      personaIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'personaId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterFilterCondition>
      personaIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'personaId',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterFilterCondition>
      personaIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'personaId',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterFilterCondition>
      personaIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'personaId',
        value: '',
      ));
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterFilterCondition>
      personaIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'personaId',
        value: '',
      ));
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterFilterCondition>
      promptIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'prompt',
      ));
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterFilterCondition>
      promptIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'prompt',
      ));
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterFilterCondition>
      promptEqualTo(
    String? value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'prompt',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterFilterCondition>
      promptGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'prompt',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterFilterCondition>
      promptLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'prompt',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterFilterCondition>
      promptBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'prompt',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterFilterCondition>
      promptStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'prompt',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterFilterCondition>
      promptEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'prompt',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterFilterCondition>
      promptContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'prompt',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterFilterCondition>
      promptMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'prompt',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterFilterCondition>
      promptIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'prompt',
        value: '',
      ));
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterFilterCondition>
      promptIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'prompt',
        value: '',
      ));
    });
  }
}

extension PersonaCollectionQueryObject
    on QueryBuilder<PersonaCollection, PersonaCollection, QFilterCondition> {}

extension PersonaCollectionQueryLinks
    on QueryBuilder<PersonaCollection, PersonaCollection, QFilterCondition> {}

extension PersonaCollectionQuerySortBy
    on QueryBuilder<PersonaCollection, PersonaCollection, QSortBy> {
  QueryBuilder<PersonaCollection, PersonaCollection, QAfterSortBy>
      sortByAvatarPath() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'avatarPath', Sort.asc);
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterSortBy>
      sortByAvatarPathDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'avatarPath', Sort.desc);
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterSortBy>
      sortByName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.asc);
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterSortBy>
      sortByNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.desc);
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterSortBy>
      sortByPersonaId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'personaId', Sort.asc);
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterSortBy>
      sortByPersonaIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'personaId', Sort.desc);
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterSortBy>
      sortByPrompt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'prompt', Sort.asc);
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterSortBy>
      sortByPromptDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'prompt', Sort.desc);
    });
  }
}

extension PersonaCollectionQuerySortThenBy
    on QueryBuilder<PersonaCollection, PersonaCollection, QSortThenBy> {
  QueryBuilder<PersonaCollection, PersonaCollection, QAfterSortBy>
      thenByAvatarPath() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'avatarPath', Sort.asc);
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterSortBy>
      thenByAvatarPathDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'avatarPath', Sort.desc);
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterSortBy>
      thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterSortBy>
      thenByName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.asc);
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterSortBy>
      thenByNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.desc);
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterSortBy>
      thenByPersonaId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'personaId', Sort.asc);
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterSortBy>
      thenByPersonaIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'personaId', Sort.desc);
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterSortBy>
      thenByPrompt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'prompt', Sort.asc);
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QAfterSortBy>
      thenByPromptDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'prompt', Sort.desc);
    });
  }
}

extension PersonaCollectionQueryWhereDistinct
    on QueryBuilder<PersonaCollection, PersonaCollection, QDistinct> {
  QueryBuilder<PersonaCollection, PersonaCollection, QDistinct>
      distinctByAvatarPath({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'avatarPath', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QDistinct> distinctByName(
      {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'name', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QDistinct>
      distinctByPersonaId({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'personaId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<PersonaCollection, PersonaCollection, QDistinct>
      distinctByPrompt({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'prompt', caseSensitive: caseSensitive);
    });
  }
}

extension PersonaCollectionQueryProperty
    on QueryBuilder<PersonaCollection, PersonaCollection, QQueryProperty> {
  QueryBuilder<PersonaCollection, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<PersonaCollection, String?, QQueryOperations>
      avatarPathProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'avatarPath');
    });
  }

  QueryBuilder<PersonaCollection, String, QQueryOperations> nameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'name');
    });
  }

  QueryBuilder<PersonaCollection, String, QQueryOperations>
      personaIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'personaId');
    });
  }

  QueryBuilder<PersonaCollection, String?, QQueryOperations> promptProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'prompt');
    });
  }
}
