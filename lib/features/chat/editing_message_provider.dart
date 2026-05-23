import 'package:flutter_riverpod/flutter_riverpod.dart';

final editingMessageIdProvider =
    StateProvider.family<String?, String>((ref, charId) => null);
