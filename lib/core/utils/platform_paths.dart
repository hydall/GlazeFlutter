import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<String> getAppDataDir() async {
  if (Platform.isAndroid || Platform.isIOS) {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, 'Glaze');
  }
  return _desktopDataDir();
}

String _desktopDataDir() {
  if (Platform.isWindows) {
    final appData = Platform.environment['APPDATA']!;
    return p.join(appData, 'Glaze');
  } else if (Platform.isLinux) {
    final xdg = Platform.environment['XDG_DATA_HOME'] ??
        p.join(Platform.environment['HOME']!, '.local', 'share');
    return p.join(xdg, 'Glaze');
  } else if (Platform.isMacOS) {
    return p.join(Platform.environment['HOME']!, 'Library',
        'Application Support', 'Glaze');
  }
  throw UnsupportedError('Platform not supported yet');
}
