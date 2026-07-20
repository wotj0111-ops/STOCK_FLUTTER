import 'package:shared_preferences/shared_preferences.dart';

/// 뉴스 열람 이력 저장소 (URL 기준).
class ReadHistoryStore {
  ReadHistoryStore._();
  static final ReadHistoryStore instance = ReadHistoryStore._();

  static const _key = 'read_news_urls_v1';
  Set<String> _cache = <String>{};
  bool _loaded = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final sp = await SharedPreferences.getInstance();
    _cache = (sp.getStringList(_key) ?? const <String>[]).toSet();
    _loaded = true;
  }

  Future<bool> isRead(String url) async {
    await _ensureLoaded();
    return _cache.contains(url);
  }

  Future<Set<String>> allRead() async {
    await _ensureLoaded();
    return Set<String>.of(_cache);
  }

  Future<void> markRead(String url) async {
    await _ensureLoaded();
    if (_cache.add(url)) {
      final sp = await SharedPreferences.getInstance();
      await sp.setStringList(_key, _cache.toList());
    }
  }

  Future<void> clear() async {
    _cache.clear();
    _loaded = true;
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_key);
  }
}
