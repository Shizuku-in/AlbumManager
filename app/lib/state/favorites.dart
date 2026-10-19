import 'package:flutter/foundation.dart';

import 'package:album_manager/src/rust/third_party/album_model.dart';
import 'package:album_manager/state/settings_controller.dart';

/// Albums the user starred, by album id (path relative to the library root).
///
/// [ids] is replaced (never mutated) on change so memoized views can key on it.
class FavoritesController extends ChangeNotifier {
  Set<String> ids = const {};

  void load() {
    ids = {...?settings.prefs.getStringList('favorites')};
  }

  bool contains(AlbumSummary a) => ids.contains(a.id);

  void toggle(AlbumSummary a) {
    ids = contains(a) ? ({...ids}..remove(a.id)) : {...ids, a.id};
    settings.prefs.setStringList('favorites', ids.toList());
    notifyListeners();
  }
}

final favorites = FavoritesController();
