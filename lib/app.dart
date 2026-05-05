import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'features/character_list/character_list_screen.dart';
import 'features/chat/chat_screen.dart';
import 'features/settings/api_settings_screen.dart';
import 'shared/theme/app_theme.dart';

final routerProvider = Provider<GoRouter>((ref) => GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const CharacterListScreen(),
        ),
        GoRoute(
          path: '/chat/:charId',
          builder: (_, state) =>
              ChatScreen(charId: state.pathParameters['charId']!),
        ),
        GoRoute(
          path: '/settings/api',
          builder: (_, __) => const ApiSettingsScreen(),
        ),
      ],
    ));

class GlazeApp extends ConsumerWidget {
  const GlazeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Glaze',
      theme: AppTheme.dark(),
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
