import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:album_manager/src/rust/third_party/album_model.dart';
import 'package:album_manager/state/settings_controller.dart';

/// Albums the user starred, by album id (path relative to the library root).
///
/// [ids] is replaced (never mutated) on change so memoized views can key on it.
class FavoritesController extends ChangeNotifier {
  Set<String> ids = const {};
  String? _key;

  Future<void> load(String? root) async {
    if (root == null) {
      _key = null;
      ids = const {};
    } else {
      var identity = root
          .replaceAll('\\', '/')
          .replaceFirst(RegExp(r'/+$'), '');
      if (Platform.isWindows) identity = identity.toLowerCase();
      _key = 'favorites.v2.$identity';
      final prefs = settings.prefs;
      // Migrate once, before the user can switch away from the saved library.
      final legacy = prefs.getStringList('favorites');
      if (legacy != null) {
        if (!prefs.containsKey(_key!) &&
            !await prefs.setStringList(_key!, legacy)) {
          throw StateError('无法迁移收藏数据');
        }
        if (!await prefs.remove('favorites')) {
          throw StateError('无法完成收藏数据迁移');
        }
      }
      ids = {...?prefs.getStringList(_key!)};
    }
    notifyListeners();
  }

  bool contains(AlbumSummary a) => ids.contains(a.id);

  void toggle(AlbumSummary a) {
    if (_key == null) return;
    ids = contains(a) ? ({...ids}..remove(a.id)) : {...ids, a.id};
    settings.prefs.setStringList(_key!, ids.toList());
    notifyListeners();
  }
}

final favorites = FavoritesController();
