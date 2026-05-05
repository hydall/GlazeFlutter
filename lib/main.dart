import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'core/db/app_db.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppDb.instance;
  runApp(const ProviderScope(child: GlazeApp()));
}
