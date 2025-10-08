import 'dart:collection';

class LRUCache<K, V> {
  final LinkedHashMap<K, V> _cache = LinkedHashMap();
  final int maxCacheSize;

  LRUCache({this.maxCacheSize = 100});

  bool containsKey(K key) => _cache.containsKey(key);

  V? operator [](K key) {
    if (!_cache.containsKey(key)) return null;
    // Move to end (most recently used) by removing and re-adding
    final value = _cache.remove(key);
    // Note that V could be nullable, something like int? - so we need to use 'as V' instead of '!'
    _cache[key] = value as V;
    return value;
  }

  void operator []=(K key, V value) {
    // Remove oldest entry if cache is full and this is a new key
    if (_cache.length >= maxCacheSize && !_cache.containsKey(key)) {
      // First key is the least recently used
      final oldestKey = _cache.keys.first;
      _cache.remove(oldestKey);
    }
    // Add entry (will be added at the end, making it most recent)
    _cache[key] = value;
  }

  V? remove(K key) => _cache.remove(key);

  void clear() {
    _cache.clear();
  }
}
