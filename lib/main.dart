import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'app.dart';
import 'core/services/generation_notification_service.dart';
import 'core/services/deep_link_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  await GenerationNotificationService.instance.init();
  await DeepLinkService.instance.init();
  runApp(const ProviderScope(child: GlazeApp()));
}
