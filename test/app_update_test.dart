import 'dart:convert';

import 'package:berea/app_update.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _sha = 'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';

String _release(String tag, {String? digest = 'sha256:$_sha', String assetName = updateAssetName}) =>
    jsonEncode({
      'tag_name': tag,
      'assets': [
        {
          'name': assetName,
          'size': 60000000,
          'digest': ?digest,
          'browser_download_url':
              'https://github.com/CalvinMagezi/berea/releases/download/$tag/$assetName',
        },
      ],
    });

void main() {
  group('versions', () {
    AppVersion v(String s) => AppVersion.tryParse(s)!;

    test('reads the forms Berea uses', () {
      expect(v('0.9.1').toString(), '0.9.1');
      expect(v('v0.9.1').toString(), '0.9.1');
      expect(v('0.8.0+8').toString(), '0.8.0');
      expect(v('0.9.0-rc1').pre, 'rc1');
      expect(AppVersion.tryParse('latest'), isNull);
      expect(AppVersion.tryParse('1.2'), isNull);
    });

    test('orders by number, not by text', () {
      expect(v('0.10.0').compareTo(v('0.9.9')), greaterThan(0));
      expect(v('1.0.0').compareTo(v('0.99.99')), greaterThan(0));
      expect(v('0.9.1').compareTo(v('0.9.1')), 0);
    });

    test('a release candidate comes before its release', () {
      expect(v('0.9.0-rc1').compareTo(v('0.9.0')), lessThan(0));
      expect(v('0.9.0-rc2').compareTo(v('0.9.0-rc10')), lessThan(0));
      expect(v('0.9.0-rc1').compareTo(v('0.8.9')), greaterThan(0));
    });
  });

  group('reading the release', () {
    test('finds the version, the file and its checksum', () {
      final r = parseLatestRelease(_release('v0.9.1'))!;
      expect(r.version.toString(), '0.9.1');
      expect(r.apk.path, endsWith('/$updateAssetName'));
      expect(r.sha256, _sha);
      expect(r.installable, isTrue);
    });

    test('a release without a checksum is found but not installable', () {
      final r = parseLatestRelease(_release('v0.9.1', digest: null))!;
      expect(r.installable, isFalse);
    });

    test('a release without the Android file, or from another host, is nothing', () {
      expect(parseLatestRelease(_release('v0.9.1', assetName: 'other.zip')), isNull);
      final elsewhere = _release('v0.9.1').replaceAll('https://github.com', 'https://example.com');
      expect(parseLatestRelease(elsewhere), isNull);
    });

    test('rubbish is nothing, not a crash', () {
      expect(parseLatestRelease('not json'), isNull);
      expect(parseLatestRelease('[]'), isNull);
      expect(parseLatestRelease(_release('nightly')), isNull);
    });
  });

  group('the service', () {
    var asked = 0;
    var now = DateTime(2026, 11, 17, 9);

    Future<UpdateService> open({
      Map<String, Object> prefs = const {},
      String answer = '',
      int status = 200,
      String installed = '0.9.0',
      bool supported = true,
    }) async {
      SharedPreferences.setMockInitialValues({...prefs});
      asked = 0;
      return UpdateService(
        await SharedPreferences.getInstance(),
        supported: supported,
        currentVersion: () async => AppVersion.tryParse(installed),
        newClient: () => MockClient((request) async {
          asked++;
          expect(request.url.toString(), latestReleaseUrl);
          expect(request.headers.keys.map((k) => k.toLowerCase()), isNot(contains('authorization')));
          return http.Response(answer, status);
        }),
        now: () => now,
      );
    }

    test('a newer release is offered', () async {
      final s = await open(answer: _release('v0.9.1'));
      await s.checkWhenOpened();
      expect(s.available?.version.toString(), '0.9.1');
    });

    test('the same or an older release is not', () async {
      final s = await open(answer: _release('v0.9.0'));
      expect(await s.check(), contains('newest'));
      expect(s.available, isNull);
    });

    test('a full release is newer than the candidate you have', () async {
      final s = await open(answer: _release('v0.9.0'), installed: '0.9.0-rc1');
      await s.check();
      expect(s.available, isNotNull);
    });

    test('off: Berea opens and asks nothing', () async {
      final s = await open(prefs: {'updateCheckOn': false}, answer: _release('v0.9.1'));
      await s.checkWhenOpened();
      expect(asked, 0);
      expect(s.available, isNull);
    });

    test('not Android: nothing is ever asked', () async {
      final s = await open(supported: false, answer: _release('v0.9.1'));
      await s.checkWhenOpened();
      await s.check();
      expect(asked, 0);
    });

    test('at most once a day when opening, but Check now always asks', () async {
      final s = await open(answer: _release('v0.9.1'));
      await s.checkWhenOpened();
      await s.checkWhenOpened();
      expect(asked, 1);
      now = now.add(const Duration(hours: 25));
      await s.checkWhenOpened();
      expect(asked, 2);
      await s.check();
      expect(asked, 3);
    });

    test('Later puts the bar away for that version, and a newer one brings it back', () async {
      final s = await open(answer: _release('v0.9.1'));
      await s.check();
      await s.later();
      expect(s.available, isNull);
      final again = UpdateService(
        s.prefs,
        supported: true,
        currentVersion: () async => AppVersion.tryParse('0.9.0'),
        newClient: () => MockClient((_) async => http.Response(_release('v0.9.2'), 200)),
      );
      await again.check();
      expect(again.available?.version.toString(), '0.9.2');
    });

    test('a failed check says so and offers nothing', () async {
      final s = await open(answer: 'oops', status: 503);
      expect(await s.check(), contains('could not reach'));
      expect(s.available, isNull);
    });

    test('turning it off removes a bar already showing', () async {
      final s = await open(answer: _release('v0.9.1'));
      await s.check();
      await s.setCheckOnOpen(false);
      expect(s.available, isNull);
      expect(s.checkOnOpen, isFalse);
    });
  });
}
