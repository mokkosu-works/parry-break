/// JSON のオブジェクトを型つきで読む。
///
/// 型や必須項目が合わないときは、どこが悪いか分かるよう
/// `campaign.json: chapters[0].stages[2].waves[1].difficulty: 整数が必要 (実際: "3")` の形で
/// [FormatException] を投げる。ステージを JSON で足すときの間違いをすぐ見つけるため。
class JsonObject {
  const JsonObject(this.map, this.path);

  /// [raw] が JSON のオブジェクトでなければ [FormatException]。
  factory JsonObject.of(Object? raw, String path) {
    if (raw is Map) return JsonObject(raw.cast<String, Object?>(), path);
    throw FormatException('$path: オブジェクトが必要 (実際: ${_show(raw)})');
  }

  final Map<String, Object?> map;
  final String path;

  bool has(String key) => map[key] != null;

  /// 必須の項目。
  T _req<T>(String key, String what) => switch (map[key]) {
        final T v => v,
        final other => throw FormatException('${_at(key)}: $whatが必要 (実際: ${_show(other)})'),
      };

  /// 省略できる項目。あれば型を確かめる。
  T? _opt<T>(String key, String what) => map[key] == null ? null : _req<T>(key, what);

  String str(String key) => _req<String>(key, '文字列');
  String? strOpt(String key) => _opt<String>(key, '文字列');

  int integer(String key) => _req<num>(key, '整数').toInt();
  int? integerOpt(String key) => _opt<num>(key, '整数')?.toInt();

  double number(String key) => _req<num>(key, '数値').toDouble();

  Map<String, Object?> mapOf(String key) => _req<Map<String, Object?>>(key, 'オブジェクト');

  JsonObject obj(String key) => JsonObject(_req<Map<Object?, Object?>>(key, 'オブジェクト').cast<String, Object?>(), _at(key));
  JsonObject? objOpt(String key) =>
      map[key] == null ? null : JsonObject(_req<Map<Object?, Object?>>(key, 'オブジェクト').cast<String, Object?>(), _at(key));

  /// オブジェクトの配列。
  List<JsonObject> objects(String key) => [
        for (final (i, v) in _req<List<Object?>>(key, '配列').indexed) JsonObject.of(v, '${_at(key)}[$i]'),
      ];

  /// オブジェクトの配列。項目がなければ空。
  List<JsonObject> objectsOpt(String key) => map[key] == null ? const [] : objects(key);

  List<String> strings(String key) => [
        for (final (i, v) in _req<List<Object?>>(key, '配列').indexed)
          v is String ? v : throw FormatException('${_at(key)}[$i]: 文字列が必要 (実際: ${_show(v)})'),
      ];
  List<String>? stringsOpt(String key) => map[key] == null ? null : strings(key);

  List<double>? numbersOpt(String key) => map[key] == null
      ? null
      : [
          for (final (i, v) in _req<List<Object?>>(key, '配列').indexed)
            v is num ? v.toDouble() : throw FormatException('${_at(key)}[$i]: 数値が必要 (実際: ${_show(v)})'),
        ];

  /// 値が整数のオブジェクト (`{"N": 1, "T": 4}`)。
  Map<String, int> intMap(String key) => {
        for (final e in _req<Map<Object?, Object?>>(key, 'オブジェクト').entries)
          '${e.key}': switch (e.value) {
            final num v => v.toInt(),
            final other => throw FormatException('${_at(key)}.${e.key}: 整数が必要 (実際: ${_show(other)})'),
          },
      };

  /// 文字列から文字列へのオブジェクト。なければ空。
  Map<String, String> stringMapOpt(String key) => map[key] == null
      ? const {}
      : {
          for (final e in _req<Map<Object?, Object?>>(key, 'オブジェクト').entries)
            '${e.key}': switch (e.value) {
              final String v => v,
              final other => throw FormatException('${_at(key)}.${e.key}: 文字列が必要 (実際: ${_show(other)})'),
            },
        };

  String _at(String key) => path.isEmpty ? key : '$path.$key';

  static String _show(Object? v) => v == null ? 'なし' : (v is String ? '"$v"' : '$v');
}
