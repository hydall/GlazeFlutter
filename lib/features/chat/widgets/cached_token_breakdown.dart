import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/llm/context_calculator.dart';

final cachedTokenBreakdownProvider =
    StateProvider.family<TokenBreakdown?, String>((ref, _) => null);
