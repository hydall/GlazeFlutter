import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glaze_flutter/features/image_gen/services/routmy_image_provider.dart';

void main() {
  group('RoutmyImageProvider Seedream references', () {
    for (final referenceCount in [1, 2]) {
      test('uses generations with $referenceCount reference(s)', () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(server.close);

        late Uri requestUri;
        late Map<String, dynamic> requestBody;
        final requestHandled = server.first.then((request) async {
          requestUri = request.uri;
          requestBody =
              jsonDecode(await utf8.decoder.bind(request).join())
                  as Map<String, dynamic>;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'data': [
                {'b64_json': 'AQ=='},
              ],
            }),
          );
          await request.response.close();
        });

        final provider = RoutmyImageProvider(
          baseUrl: 'http://${server.address.host}:${server.port}',
        );
        final references = List.generate(referenceCount, (_) => 'iVBORw0KGgo=');

        final bytes = await provider.generate(
          apiKey: 'test-key',
          model: 'bytedance/seedream-5.0-pro',
          prompt: 'test prompt',
          aspectRatio: '1:1',
          imageSize: '1K',
          quality: 'auto',
          referenceImages: references,
        );
        await requestHandled;

        expect(requestUri.path, '/v1/images/generations');
        expect(bytes, [1]);
        final expectedRef = 'data:image/png;base64,${references.first}';
        if (referenceCount == 1) {
          expect(requestBody['image'], expectedRef);
        } else {
          expect(requestBody['image'], [expectedRef, expectedRef]);
        }
      });
    }
  });
}
