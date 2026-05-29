import '../llm/embedding_service.dart';
import '../llm/sse_client.dart';

sealed class ApiTestResult {
  const ApiTestResult();
}

class ApiTestSuccess extends ApiTestResult {
  final String message;
  const ApiTestSuccess(this.message);
}

class ApiTestFailure extends ApiTestResult {
  final Object error;
  const ApiTestFailure(this.error);
}

class ApiConnectionTester {
  final SseClient _client = SseClient();

  Future<ApiTestResult> testLlm({
    required String endpoint,
    required String apiKey,
    required String model,
  }) async {
    try {
      final models = await _client.fetchModels(
        endpoint: endpoint,
        apiKey: apiKey,
      );
      if (models.isEmpty) {
        String? responseText;
        await _client.streamChatCompletion(
          endpoint: endpoint,
          apiKey: apiKey,
          model: model,
          messages: [
            {'role': 'user', 'content': 'Hi'},
          ],
          maxTokens: 8,
          temperature: 0.0,
          topP: 1.0,
          stream: false,
          onComplete: (text, _, {rawResponseJson}) => responseText = text,
          onError: (e) => throw e,
        );
        if (responseText != null) {
          return const ApiTestSuccess('Connection successful!');
        }
        return const ApiTestFailure('No response from model');
      }
      final exists = models.any((m) => m['id'] == model);
      return exists
          ? ApiTestSuccess('Connection successful! Model "$model" found.')
          : ApiTestSuccess('Connected, but "$model" not found.');
    } catch (e) {
      return ApiTestFailure(e);
    }
  }

  Future<ApiTestResult> testEmbedding({
    required String endpoint,
    required String apiKey,
    required String model,
    int maxChunkTokens = 64,
  }) async {
    try {
      final config = EmbeddingConfig(
        endpoint: endpoint,
        apiKey: apiKey,
        model: model,
        maxChunkTokens: maxChunkTokens,
      );
      final result = await EmbeddingService().getEmbeddings(['test'], config);
      if (result.isNotEmpty && result.first.isNotEmpty) {
        return ApiTestSuccess('Connected (dim: ${result.first.length})');
      }
      return const ApiTestFailure('Empty response from embedding API');
    } catch (e) {
      return ApiTestFailure(e);
    }
  }
}
