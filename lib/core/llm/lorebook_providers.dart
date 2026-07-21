/// Riverpod providers for lorebook embedding and vector search.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/api_config.dart';
import '../../features/settings/api_list_provider.dart';
import '../state/db_provider.dart';
import 'embedding_service.dart';
import 'embedding_request_gate.dart';
import 'lorebook_embedding_service.dart';
import 'lorebook_vector_search.dart';

final embeddingConfigProvider = Provider<EmbeddingConfig>((ref) {
  final chatConfig = ref.watch(activeApiConfigProvider);
  EmbeddingRequestGate.setEnabled(chatConfig?.embeddingEnabled == true);
  return resolveEmbeddingConfig(chatConfig);
});

EmbeddingConfig resolveEmbeddingConfig(ApiConfig? chatConfig) {
  if (chatConfig == null ||
      chatConfig.mode == 'embedding' ||
      !chatConfig.embeddingEnabled) {
    return const EmbeddingConfig(endpoint: '', model: '');
  }
  if (chatConfig.embeddingUseSame || chatConfig.embeddingEndpoint.isEmpty) {
    return EmbeddingConfig(
      endpoint: chatConfig.endpoint,
      apiKey: chatConfig.apiKey,
      model: chatConfig.embeddingModel.isNotEmpty
          ? chatConfig.embeddingModel
          : chatConfig.model,
      maxChunkTokens: chatConfig.embeddingMaxChunkTokens,
    );
  } else {
    return EmbeddingConfig(
      endpoint: chatConfig.embeddingEndpoint,
      apiKey: chatConfig.embeddingApiKey,
      model: chatConfig.embeddingModel,
      maxChunkTokens: chatConfig.embeddingMaxChunkTokens,
    );
  }
}

final lorebookVectorSearchProvider = Provider<LorebookVectorSearch>((ref) {
  return LorebookVectorSearch(
    ref.watch(embeddingRepoProvider),
    EmbeddingService(),
  );
});

final lorebookEmbeddingServiceProvider = Provider<LorebookEmbeddingService>((
  ref,
) {
  return LorebookEmbeddingService(
    ref.watch(embeddingRepoProvider),
    EmbeddingService(),
  );
});
