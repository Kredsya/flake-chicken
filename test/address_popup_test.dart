import 'dart:async';
import 'dart:convert';

import 'package:flake_chicken/data/backend_api.dart';
import 'package:flake_chicken/data/local_store.dart';
import 'package:flake_chicken/platform/bridge.dart';
import 'package:flake_chicken/ui/screens/settings_screen.dart';
import 'package:flake_chicken/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _PopupPlatform extends PlatformBridge {
  bool prepared = false;
  int launches = 0;
  int closes = 0;
  bool closeImmediately = false;
  final done = Completer<void>();
  @override
  void prepareAddressPopup() => prepared = true;
  @override
  Future<void> addressPopup(Map<String, dynamic> launch) {
    launches++;
    return closeImmediately ? Future.value() : done.future;
  }

  @override
  Future<void> cancelAddressPopup() async {
    closes++;
    if (!done.isCompleted) done.complete();
  }

  @override
  Future<Map<String, dynamic>> identity() async => {
    'uid': 'test',
    'salt': 'test',
    'publicKey': 'test',
    'platform': 'android',
  };
  @override
  Future<String> sign(String payload) async => 'test';
  @override
  Stream<void> get changes => const Stream.empty();
  @override
  Future<Map<String, dynamic>> notifications(
    String publicKey, {
    bool request = false,
  }) async => {'supported': true, 'enabled': false};
}

http.Response _json(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json'},
);
const _launch = {
  'id': 'popup-id',
  'url': 'https://35.212.249.154/address-popup/popup-id/token',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('popup opens before request, delivers without opener and deletes temporary result', () async {
    final platform = _PopupPlatform();
    var deleted = false;
    final api = BackendApi(
      platform: platform,
      client: MockClient((request) async {
        if (request.method == 'POST') {
          expect(platform.prepared, isTrue);
          return _json(_launch);
        }
        if (request.method == 'DELETE') {
          deleted = true;
          return http.Response('', 204);
        }
        return _json({
          'ready': true,
          'address': {'roadAddress': '서울특별시 종로구 세종대로 209', 'zipCode': '03171'},
        });
      }),
    );
    addTearDown(api.dispose);
    expect(await api.pickAddress(), '서울특별시 종로구 세종대로 209');
    expect(platform.launches, 1);
    expect(platform.closes, 1);
    expect(deleted, isTrue);
  });
  test('closing without selection preserves the field; failed launch closes preopened window', () async {
    final platform = _PopupPlatform()..closeImmediately = true;
    final api = BackendApi(
      platform: platform,
      client: MockClient((request) async {
        if (request.method == 'POST') return _json(_launch);
        if (request.method == 'DELETE') return http.Response('', 204);
        return _json({'ready': false, 'address': null});
      }),
    );
    addTearDown(api.dispose);
    expect(await api.pickAddress(), isNull);
    expect(platform.closes, 1);
    final missing = _PopupPlatform();
    final failed = BackendApi(
      platform: missing,
      client: MockClient((_) async => _json({'message': '주소 검색 준비 중'}, 503)),
    );
    addTearDown(failed.dispose);
    await expectLater(failed.pickAddress(), throwsStateError);
    expect(missing.closes, 1);
  });
  test(
    'cancel while session is being created never opens the provider page',
    () async {
      final platform = _PopupPlatform();
      final response = Completer<http.Response>();
      var deleted = false;
      final api = BackendApi(
        platform: platform,
        client: MockClient((request) async {
          if (request.method == 'POST') return response.future;
          deleted = true;
          return http.Response('', 204);
        }),
      );
      addTearDown(api.dispose);
      final picking = api.pickAddress();
      await api.cancelAddressSearch();
      response.complete(_json(_launch));
      expect(await picking, isNull);
      expect(platform.launches, 0);
      expect(deleted, isTrue);
    },
  );
  testWidgets(
    'choosing an official address autosaves only the chosen profile slot',
    (tester) async {
      final storage = MemoryStorage()
        ..value = jsonEncode({
          'profiles': {
            'names': ['이름', '', ''],
            'addresses': ['기존 주소', '둘째 주소', '셋째 주소'],
            'gmgMode': false,
          },
        });
      final api = BackendApi(
        platform: _PopupPlatform(),
        client: MockClient((request) async {
          final path = request.url.path;
          if (path.endsWith('/challenge')) {
            return _json({'id': 'x', 'payload': 'proof'});
          }
          if (path.endsWith('/verify')) return _json({'token': 'session'});
          if (path == '/api/config') return _json({});
          if (path == '/api/appointments') return _json({'appointments': []});
          if (path == '/api/address-popup') return _json(_launch);
          if (request.method == 'DELETE') return http.Response('', 204);
          return _json({
            'ready': true,
            'address': {
              'roadAddress': '서울특별시 종로구 세종대로 209',
              'zipCode': '03171',
            },
          });
        }),
      );
      final store = await AppStore.connect(storage, api: api);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: SettingsScreen(store: store),
        ),
      );
      await tester.pumpAndSettle();
      final button = find.byKey(const ValueKey('search-profile-address-0'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(store.profiles.addresses, [
        '서울특별시 종로구 세종대로 209',
        '둘째 주소',
        '셋째 주소',
      ]);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
      await tester.pump(const Duration(seconds: 4));
    },
  );
}
