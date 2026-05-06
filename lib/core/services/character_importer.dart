import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../models/character.dart';
import 'image_storage_service.dart';
import 'png_text_extractor.dart';

class CharacterImportResult {
  final Character character;
  final bool hadAvatar;
  final Map<String, dynamic>? characterBookData;

  CharacterImportResult({required this.character, required this.hadAvatar, this.characterBookData});
}

class CharacterImporter {
  final ImageStorageService _imageStorage;

  CharacterImporter(this._imageStorage);

  Future<CharacterImportResult> importFromFile(String filePath) async {
    final ext = p.extension(filePath).toLowerCase();
    final file = File(filePath);
    final bytes = await file.readAsBytes();

    if (ext == '.png') {
      return _importPng(bytes);
    } else if (ext == '.charx' || ext == '.zip') {
      return _importCharX(bytes);
    } else {
      return _importJson(bytes);
    }
  }

  Future<CharacterImportResult> importFromBytes(
      Uint8List bytes, String fileName) async {
    final ext = p.extension(fileName).toLowerCase();

    if (ext == '.png') {
      return _importPng(bytes);
    } else if (ext == '.charx' || ext == '.zip') {
      return _importCharX(bytes);
    } else {
      return _importJson(bytes);
    }
  }

  Future<CharacterImportResult> _importPng(Uint8List pngBytes) async {
    final rawData = extractCharacterDataFromPng(pngBytes);
    if (rawData == null) {
      throw FormatException('No character data found in PNG tEXt chunks');
    }

    final data = _normalizeCharacterData(rawData);
    final character = await _saveCharacterWithAvatar(data, pngBytes);
    return CharacterImportResult(
        character: character, hadAvatar: true,
        characterBookData: data['character_book'] as Map<String, dynamic>?);
  }

  Future<CharacterImportResult> _importJson(Uint8List jsonBytes) async {
    final jsonString = utf8.decode(jsonBytes);
    final rawJson = jsonDecode(jsonString) as Map<String, dynamic>;
    final data = _normalizeCharacterData(rawJson);

    Uint8List? avatarBytes;
    final avatarSrc = data['avatar'] as String?;
    if (avatarSrc != null && avatarSrc.isNotEmpty) {
      avatarBytes = _dataUrlToBytes(avatarSrc);
    }

    final character = await _saveCharacterWithAvatar(data, avatarBytes);
    return CharacterImportResult(
        character: character, hadAvatar: avatarBytes != null,
        characterBookData: data['character_book'] as Map<String, dynamic>?);
  }

  Future<CharacterImportResult> _importCharX(Uint8List zipBytes) async {
    final archive = ZipDecoder().decodeBytes(zipBytes);

    String? cardJsonContent;
    final assetFiles = <String, Uint8List>{};

    for (final file in archive) {
      if (file.isFile) {
        final content = Uint8List.fromList(file.content as List<int>);
        if (p.basename(file.name) == 'card.json') {
          cardJsonContent = utf8.decode(content);
        } else {
          assetFiles[file.name] = content;
        }
      }
    }

    if (cardJsonContent == null) {
      throw FormatException('No card.json found in CharX archive');
    }

    final rawJson = jsonDecode(cardJsonContent) as Map<String, dynamic>;
    final data = _normalizeCharacterData(rawJson);

    Uint8List? avatarBytes;
    final assets = data['assets'] as List<dynamic>?;
    if (assets != null) {
      for (final asset in assets) {
        final assetMap = asset as Map<String, dynamic>;
        final type = assetMap['type'] as String?;
        final uri = assetMap['uri'] as String?;

        if (type == 'icon' && uri != null) {
          final zipPath = _resolveEmbeddedUri(uri);
          if (assetFiles.containsKey(zipPath)) {
            avatarBytes = assetFiles[zipPath]!;
            break;
          }
        }
      }
    }

    if (avatarBytes == null) {
      final avatarSrc = data['avatar'] as String?;
      if (avatarSrc != null && avatarSrc.isNotEmpty) {
        avatarBytes = _dataUrlToBytes(avatarSrc);
      }
    }

    final character = await _saveCharacterWithAvatar(data, avatarBytes);
    return CharacterImportResult(
        character: character, hadAvatar: avatarBytes != null,
        characterBookData: data['character_book'] as Map<String, dynamic>?);
  }

  Map<String, dynamic> _normalizeCharacterData(Map<String, dynamic> json) {
    final spec = json['spec'] as String?;
    if (spec == 'chara_card_v2' || spec == 'chara_card_v3') {
      final data = json['data'] as Map<String, dynamic>?;
      if (data != null) return Map<String, dynamic>.from(data);
    }
    if (json.containsKey('name') || json.containsKey('data')) {
      if (json.containsKey('data') && json['data'] is Map) {
        return Map<String, dynamic>.from(json['data'] as Map);
      }
      return Map<String, dynamic>.from(json);
    }
    throw FormatException('Unknown character data format');
  }

  Future<Character> _saveCharacterWithAvatar(
      Map<String, dynamic> data, Uint8List? avatarBytes) async {
    final id = _generateId();
    String? avatarPath;

    if (avatarBytes != null) {
      avatarPath = await _imageStorage.saveAvatar(id, avatarBytes);
    } else {
      final avatarSrc = data['avatar'] as String?;
      if (avatarSrc != null && avatarSrc.isNotEmpty) {
        avatarPath =
            await _imageStorage.saveAvatarFromDataUrl(id, avatarSrc);
      }
    }

    return Character(
      id: id,
      name: (data['name'] as String?) ?? 'Unknown',
      avatarPath: avatarPath,
      description: data['description'] as String?,
      personality: data['personality'] as String?,
      scenario: data['scenario'] as String?,
      firstMes: data['first_mes'] as String?,
      mesExample: data['mes_example'] as String?,
      systemPrompt: data['system_prompt'] as String?,
      postHistoryInstructions: data['post_history_instructions'] as String?,
      creator: data['creator'] as String?,
      creatorNotes: data['creator_notes'] as String?,
      color: data['color'] as String?,
      tags: _toStringList(data['tags']),
      alternateGreetings: _toStringList(data['alternate_greetings']),
      updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
  }

  String _generateId() {
    return DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  }

  List<String> _toStringList(dynamic value) {
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    return [];
  }

  Uint8List? _dataUrlToBytes(String dataUrl) {
    if (!dataUrl.startsWith('data:')) return null;
    final commaIndex = dataUrl.indexOf(',');
    if (commaIndex == -1) return null;
    final base64Str = dataUrl.substring(commaIndex + 1);
    try {
      return base64Decode(base64Str);
    } catch (_) {
      return null;
    }
  }

  String _resolveEmbeddedUri(String uri) {
    if (uri.startsWith('embedded://')) {
      return uri.substring('embedded://'.length);
    }
    if (uri.startsWith('embeded://')) {
      return uri.substring('embeded://'.length);
    }
    if (uri.startsWith('__asset:')) {
      return uri.substring('__asset:'.length);
    }
    return uri;
  }
}
