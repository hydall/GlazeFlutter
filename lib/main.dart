import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'app.dart';
import 'package:glaze_flutter/core/llm/tokenizer.dart';
import 'package:glaze_flutter/core/llm/prompt_worker.dart';
import 'core/services/generation_notification_service.dart';
import 'core/services/deep_link_service.dart';

final appRestartKey = GlobalKey();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  await dotenv.load(fileName: '.env');
  await preloadO200kBase();
  await PromptWorker.ensureInitialized();
  await GenerationNotificationService.instance.init();
  await DeepLinkService.instance.init();
  runApp(const _RestartableApp());
}

class _RestartableApp extends StatefulWidget {
  const _RestartableApp();

  @override
  State<_RestartableApp> createState() => _RestartableAppState();
}

class _RestartableAppState extends State<_RestartableApp> {
  Key _key = UniqueKey();

  void restart() => setState(() => _key = UniqueKey());

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: _key,
      child: ProviderScope(child: GlazeApp(restart: restart)),
    );
  }
}
