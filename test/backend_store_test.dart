import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flake_chicken/data/backend_api.dart';
import 'package:flake_chicken/data/local_store.dart';
import 'package:flake_chicken/models/appointment.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.flakechicken/platform');
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => switch (call.method) {
            'identity' => {
              'uid': 'installation',
              'salt': 'salt',
              'publicKey': 'key',
              'platform': 'android',
            },
            'sign' => 'signature',
            'notifications' => {'supported': true, 'enabled': false},
            _ => null,
          },
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.flakechicken/events'),
          (call) async => null,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.flakechicken/events'),
          null,
        );
  });

  test('connected store sends UTC and only the selected profile; local storage excludes meetings and Maps data', () async {
    Map<String, dynamic>? appointment;
    Map<String, dynamic>? createdBody;
    final api = BackendApi(
      client: MockClient((request) async {
        final path = request.url.path;
        dynamic result;
        if (path == '/api/auth/challenge') {
          result = {'id': 'challenge', 'payload': 'sign me'};
        } else if (path == '/api/auth/verify') {
          result = {'token': 'session'};
        } else if (path == '/api/config') {
          result = {'webPushPublicKey': 'vapid'};
        } else if (path == '/api/events') {
          return http.Response('', 404);
        } else if (path == '/api/appointments' && request.method == 'POST') {
          createdBody = jsonDecode(request.body) as Map<String, dynamic>;
          result = appointment =
              {
                  ...createdBody!,
                  'id': 'meeting',
                  'invitationCode': 'ABCD2345',
                  'isOwner': true,
                  'isCancelled': false,
                  'myChoice': createdBody!['choice'],
                  'participantCount': 1,
                  'version': 1,
                  'routeVariant': 0,
                }
                ..remove('requestId')
                ..remove('choice');
        } else if (path.endsWith('/route')) {
          result = {
            'durationMinutes': 39,
            'mapBase64': base64Encode([1, 2, 3]),
          };
        } else {
          result = {
            'appointments': [?appointment],
          };
        }
        return http.Response(
          jsonEncode(result),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final storage = MemoryStorage();
    final store = await AppStore.connect(storage, api: api);
    addTearDown(store.dispose);
    expect(store.appointments, isEmpty);
    expect(store.profilesReady, isFalse);
    await store.saveProfiles(
      ProfileSettings(
        names: ['첫째', '둘째', ''],
        addresses: ['출발 하나', '', '출발 셋'],
        gmgMode: true,
      ),
    );
    final date = DateTime(2026, 11, 20, 19, 30);
    await store.createAppointment(
      title: '서버 약속',
      startsAt: date,
      destination: '목적지',
      nameIndex: 1,
      addressIndex: 2,
    );
    expect(createdBody!['displayName'], '둘째');
    expect(createdBody!['origin'], '출발 셋');
    expect(createdBody!['choice'], isTrue);
    expect(createdBody!['startsAt'], date.toUtc().toIso8601String());
    expect(store.appointments.single.myChoice, isTrue);
    expect(store.appointments.single.isCancelled, isFalse);
    expect(store.appointments.single.connected, isTrue);
    await store.saveProfiles(
      ProfileSettings(names: ['변경', '', ''], addresses: ['다른 주소', '', '']),
    );
    expect(store.appointments.single.origin, '출발 셋');
    expect(storage.value, isNot(contains('서버 약속')));
    expect(storage.value, isNot(contains('mapBase64')));
    expect(storage.value, isNot(contains('appointments')));
  });

  test(
    '204 deletion succeeds and a 401 renews identity before retry',
    () async {
      var calls = 0;
      var auth = 0;
      final api = BackendApi(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/challenge')) {
            return http.Response('{"id":"x","payload":"proof"}', 200);
          }
          if (request.url.path.endsWith('/verify')) {
            auth++;
            return http.Response('{"token":"new"}', 200);
          }
          calls++;
          return calls == 1
              ? http.Response('{"message":"expired"}', 401)
              : http.Response('', 204);
        }),
      );
      addTearDown(api.dispose);
      expect(await api.request('DELETE', '/api/appointments/x'), isNull);
      expect(auth, 1);
      expect(calls, 2);
    },
  );
}
