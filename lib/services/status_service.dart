import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/status_item.dart';

enum WaApp {
  whatsapp('com.whatsapp', 'WhatsApp'),
  business('com.whatsapp.w4b', 'WA Business');

  const WaApp(this.pkg, this.label);
  final String pkg;
  final String label;
}

/// Talks to the native layer (MainActivity.kt) and holds the app state.
class StatusService extends ChangeNotifier {
  static const _channel = MethodChannel('status_saver/saf');
  static const _prefApp = 'wa_app';

  WaApp app = WaApp.whatsapp;
  bool installed = true;
  bool hasPermission = false;
  bool loading = true;
  String? error;

  List<StatusItem> statuses = [];
  List<StatusItem> saved = [];

  List<StatusItem> get images => statuses.where((s) => !s.isVideo).toList();
  List<StatusItem> get videos => statuses.where((s) => s.isVideo).toList();

  /// Names of files already saved, used to show the "saved" check mark.
  Set<String> get savedNames => saved.map((s) => s.name).toSet();

  final Map<String, Future<String>> _fileCache = {};
  final Map<String, Future<String?>> _thumbCache = {};

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefApp);
    app = WaApp.values.firstWhere((a) => a.pkg == stored, orElse: () => WaApp.whatsapp);
    await refresh();
  }

  Future<void> switchApp(WaApp next) async {
    if (next == app) return;
    app = next;
    statuses = [];
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefApp, next.pkg);
    await refresh();
  }

  Map<String, Object> get _args => {'pkg': app.pkg};

  Future<void> refresh() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      installed = await _channel.invokeMethod<bool>('isInstalled', _args) ?? false;
      hasPermission = await _channel.invokeMethod<bool>('hasPermission', _args) ?? false;
      if (hasPermission) {
        final list = await _channel.invokeListMethod<Map>('listStatuses', _args) ?? [];
        statuses = list.map(StatusItem.fromMap).toList();
      } else {
        statuses = [];
      }
      await _loadSaved(notify: false);
    } on PlatformException catch (e) {
      error = e.message;
    }
    loading = false;
    notifyListeners();
  }

  Future<void> _loadSaved({bool notify = true}) async {
    final list = await _channel.invokeListMethod<Map>('listSaved') ?? [];
    saved = list.map(StatusItem.fromMap).toList();
    if (notify) notifyListeners();
  }

  Future<bool> requestPermission() async {
    final ok = await _channel.invokeMethod<bool>('requestPermission', _args) ?? false;
    await refresh();
    return ok;
  }

  /// Local file path for [item] (copied into the app cache when needed).
  Future<String> localPath(StatusItem item) => _fileCache.putIfAbsent(
        item.uri,
        () async {
          final path = await _channel.invokeMethod<String>(
            'cacheFile',
            {'uri': item.uri, 'name': item.name},
          );
          return path!;
        },
      );

  Future<String?> thumbnail(StatusItem item) => _thumbCache.putIfAbsent(
        item.uri,
        () => _channel.invokeMethod<String>(
          'videoThumbnail',
          {'uri': item.uri, 'name': item.name},
        ).catchError((_) => null),
      );

  bool isSaved(StatusItem item) => savedNames.contains(item.name);

  Future<void> save(StatusItem item) async {
    if (isSaved(item)) return;
    await _channel.invokeMethod('save', {
      'uri': item.uri,
      'name': item.name,
      'isVideo': item.isVideo,
    });
    await _loadSaved();
  }

  Future<void> delete(StatusItem item) async {
    await _channel.invokeMethod('delete', {'uri': item.uri});
    _fileCache.remove(item.uri);
    await _loadSaved();
  }

  /// Shares via the system sheet, or directly to [targetPkg] (e.g. repost to WhatsApp).
  Future<void> share(StatusItem item, {String? targetPkg}) async {
    final path = await localPath(item);
    await _channel.invokeMethod('share', {
      'path': path,
      'isVideo': item.isVideo,
      'target': targetPkg,
    });
  }
}
