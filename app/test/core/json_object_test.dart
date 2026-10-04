import 'package:flutter_test/flutter_test.dart';
import 'package:ricochet/core/core.dart';

void main() {
  group('JsonObject', () {
    test('型や必須項目が合わないときは、場所つきのエラーになる', () {
      final j = JsonObject.of({'a': '3', 'list': [1]}, 'x.json');
      expect(() => j.integer('a'), throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('x.json.a: 整数が必要'))));
      expect(() => j.str('missing'), throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('x.json.missing'))));
      expect(() => j.strings('list'), throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('x.json.list[0]'))));
    });

    test('省略できる項目は、なければ null', () {
      final j = JsonObject.of({'n': 2}, 'x.json');
      expect(j.integerOpt('none'), isNull);
      expect(j.integerOpt('n'), 2);
      expect(j.objectsOpt('none'), isEmpty);
    });
  });

  group('ステージ定義の書き間違い', () {
    final endless = (() {
      return EndlessContent.fromJson({
        'wavesPerLoop': 60,
        'bossEvery': 10,
        'loopSpeedup': 0.1,
        'generator': {'unlock': {'N': 1}},
        'handcrafted': <String, Object?>{},
        'bosses': <Object?>[],
      });
    })();

    Map<String, Object?> campaign(Map<String, Object?> wave, {List<Object?>? stars}) => {
          'chapters': [
            {
              'id': 'c1',
              'title': 'T',
              'stages': [
                {'id': '1-1', 'title': 'S', 'waves': [wave], 'stars': ?stars},
              ],
            },
          ],
        };

    test('星の条件が不明なら、場所つきのエラー', () {
      expect(
        () => Campaign.fromJson(campaign({'endless': 1}, stars: [{'type': 'oops', 'value': 1}]), endless),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('stars[0].type'))),
      );
    });

    test('ウェーブに中身がなければエラー', () {
      expect(() => Campaign.fromJson(campaign({}), endless), throwsA(isA<FormatException>()));
    });

    test('存在しないボスを指すとエラー', () {
      expect(() => Campaign.fromJson(campaign({'boss': 3}), endless), throwsA(isA<FormatException>()));
    });

    test('星を省略すると「クリア」だけ', () {
      final c = Campaign.fromJson(campaign({'endless': 2}), endless);
      expect(c.stages.single.stars, hasLength(1));
    });
  });
}
