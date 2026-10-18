/// Remembers the result for the last input, compared by identity / equality.
///
/// Derived data (filtered lists, statistics) is recomputed only when the
/// album list or the relevant options actually change, not on every rebuild.
class Memo<K, V> {
  K? _key;
  V? _value;
  bool _filled = false;

  V call(K key, V Function() compute) {
    if (!_filled || !(identical(key, _key) || key == _key)) {
      _key = key;
      _value = compute();
      _filled = true;
    }
    return _value as V;
  }
}
