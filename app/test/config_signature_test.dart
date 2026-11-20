/// 远端配置签名 —— 纯 Dart HMAC-SHA256 的自测。
///
/// 最重要的一条是「真实配置文件」那组：它用 **Dart 侧**的验签去校验
/// **python 侧**（`scripts/sign-config.sh`）签出来的文件。
/// 只要两边的规范化规则差一个字节，这条测试就会红 —— 跨语言一致性被锁死。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:kmlab_toolbox/config/config_loader.dart';
import 'package:kmlab_toolbox/config/config_signature.dart';
import 'package:kmlab_toolbox/model/app_config.dart';

void main() {
  group('SHA-256 已知向量', () {
    test('空串', () {
      expect(
        ConfigSignature.sha256Bytes(const []).map(_hex).join(),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
    });

    test('"abc"', () {
      expect(
        ConfigSignature.sha256Bytes(utf8.encode('abc')).map(_hex).join(),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });

    test('长句（跨 64 字节块）', () {
      expect(
        ConfigSignature.sha256Bytes(
          utf8.encode('The quick brown fox jumps over the lazy dog'),
        ).map(_hex).join(),
        'd7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592',
      );
    });

    test('正好 55 / 56 / 64 字节（补位边界）', () {
      for (final n in [55, 56, 64, 119, 120]) {
        final msg = 'a' * n;
        // 只断言长度与确定性（具体值由上面三条向量覆盖算法正确性）
        final h = ConfigSignature.sha256Bytes(utf8.encode(msg)).map(_hex).join();
        expect(h.length, 64);
        expect(h, ConfigSignature.sha256Bytes(utf8.encode(msg)).map(_hex).join());
      }
    });
  });

  group('HMAC-SHA256（RFC 4231 向量）', () {
    test('case 1', () {
      final key = List<int>.filled(20, 0x0b);
      expect(
        ConfigSignature.hmacSha256Hex(
          String.fromCharCodes(key),
          'Hi There',
        ),
        'b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7',
      );
    });

    test('case 2（Jefe）', () {
      expect(
        ConfigSignature.hmacSha256Hex('Jefe', 'what do ya want for nothing?'),
        '5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843',
      );
    });

    test('case 3（二进制 key 触发预哈希）', () {
      expect(
        ConfigSignature.hmacSha256Raw(
          List<int>.filled(20, 0xaa),
          List<int>.filled(50, 0xdd),
        ),
        '773ea91e36800e46854db8ebd09181a72959098b3ef8c122d9635514ced565fe',
      );
    });

    test('case 6（超长二进制 key）', () {
      expect(
        ConfigSignature.hmacSha256Raw(
          List<int>.filled(131, 0xaa),
          utf8.encode('Test Using Larger Than Block-Size Key - Hash Key First'),
        ),
        '60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54',
      );
    });
  });

  group('规范化 JSON', () {
    test('键按字典序排序', () {
      expect(
        ConfigSignature.canonicalJson({'b': 1, 'a': 2}),
        '{"a":2,"b":1}',
      );
    });

    test('嵌套对象也排序', () {
      expect(
        ConfigSignature.canonicalJson({
          'z': {'y': 1, 'x': 2},
          'a': 3,
        }),
        '{"a":3,"z":{"x":2,"y":1}}',
      );
    });

    test('数组保持原顺序', () {
      expect(
        ConfigSignature.canonicalJson([3, 1, 2]),
        '[3,1,2]',
      );
    });

    test('中文不转义', () {
      expect(
        ConfigSignature.canonicalJson({'名': '打卡助手'}),
        '{"名":"打卡助手"}',
      );
    });

    test('null / bool / 数字', () {
      expect(
        ConfigSignature.canonicalJson({
          'a': null,
          'b': true,
          'c': false,
          'd': 8000,
        }),
        '{"a":null,"b":true,"c":false,"d":8000}',
      );
    });
  });

  group('签名 / 验签', () {
    test('往返一致', () {
      final cfg = <String, dynamic>{
        'schemaVersion': 1,
        'app': {'name': 'kmlab'},
        'tools': [
          {'id': 'water', 'title': '每日喝水'},
        ],
      };
      final sig = ConfigSignature.sign(cfg);
      expect(sig.length, 64);
      expect(ConfigSignature.verify({...cfg, 'signature': sig}), isTrue);
    });

    test('签名字段本身不参与签名', () {
      final cfg = <String, dynamic>{'a': 1};
      final sig = ConfigSignature.sign(cfg);
      expect(ConfigSignature.sign({...cfg, 'signature': sig}), sig);
    });

    test('内容改一个字节就验不过', () {
      final cfg = <String, dynamic>{'a': 1, 'b': 2};
      final sig = ConfigSignature.sign(cfg);
      expect(ConfigSignature.verify({...cfg, 'b': 3, 'signature': sig}), isFalse);
    });

    test('缺签名字段 → 验不过', () {
      expect(ConfigSignature.verify({'a': 1}), isFalse);
    });

    test('空签名 → 验不过', () {
      expect(ConfigSignature.verify({'a': 1, 'signature': ''}), isFalse);
    });

    test('错误密钥 → 验不过', () {
      final cfg = <String, dynamic>{'a': 1};
      final sig = ConfigSignature.sign(cfg);
      expect(
        ConfigSignature.verify({...cfg, 'signature': sig}, secret: 'wrong'),
        isFalse,
      );
    });
  });

  group('加载器的签名闸门', () {
    late ConfigLoader loader;

    setUp(() {
      loader = ConfigLoader();
    });

    tearDown(() {
      loader.dispose();
    });

    test('签名正确 → 放行', () {
      final cfg = AppConfig.parse(File('../config/app.config.json').readAsStringSync());
      expect(cfg.remote.requireSignature, isTrue,
          reason: '配置里签名校验应该是开着的');
      final parsed = loader.parseAndValidate(
        File('../config/app.config.json').readAsStringSync(),
        requireSignature: true,
      );
      expect(parsed, isNotNull);
    });

    test('签名正确但强制校验 → 仍然放行', () {
      final parsed = loader.parseAndValidate(
        File('../config/app.config.json').readAsStringSync(),
        requireSignature: true,
      );
      expect(parsed, isNotNull);
    });

    test('内容被改 → 拒绝', () {
      final map = jsonDecode(
        File('../config/app.config.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      (map['app'] as Map<String, dynamic>)['appName'] = '被改了';
      final parsed = loader.parseAndValidate(
        jsonEncode(map),
        requireSignature: true,
      );
      expect(parsed, isNull);
    });

    test('签名被删 → 拒绝', () {
      final map = jsonDecode(
        File('../config/app.config.json').readAsStringSync(),
      ) as Map<String, dynamic>..remove('signature');
      final parsed = loader.parseAndValidate(
        jsonEncode(map),
        requireSignature: true,
      );
      expect(parsed, isNull);
    });

    test('不要求签名时（内置快照 / last-good）照样放行', () {
      final parsed = loader.parseAndValidate(
        File('../config/app.config.json').readAsStringSync(),
      );
      expect(parsed, isNotNull);
    });
  });

  group('真实配置文件（Dart 验 python 签的）', () {
    late Map<String, dynamic> raw;

    setUpAll(() {
      final text = File('../config/app.config.json').readAsStringSync();
      raw = jsonDecode(text) as Map<String, dynamic>;
    });

    test('仓库里的配置带签名字段', () {
      expect(raw['signature'], isA<String>());
      expect((raw['signature'] as String).length, 64);
    });

    test('Dart 侧能验过 python 签的签名（跨语言一致）', () {
      expect(
        ConfigSignature.verify(raw),
        isTrue,
        reason: 'scripts/sign-config.sh（python）与 config_signature.dart（dart）'
            '的规范化规则必须逐字节一致',
      );
    });

    test('改一个字段就验不过', () {
      final tampered = jsonDecode(jsonEncode(raw)) as Map<String, dynamic>;
      (tampered['app'] as Map<String, dynamic>)['appName'] = '被改了';
      expect(ConfigSignature.verify(tampered), isFalse);
    });

    test('去掉 signature 就验不过', () {
      final noSig = jsonDecode(jsonEncode(raw)) as Map<String, dynamic>..remove('signature');
      expect(ConfigSignature.verify(noSig), isFalse);
    });
  });
}

String _hex(int b) => (b & 0xff).toRadixString(16).padLeft(2, '0');
