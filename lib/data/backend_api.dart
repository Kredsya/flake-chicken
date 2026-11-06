import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../platform/bridge.dart';

class BackendApi {
  BackendApi({http.Client? client, PlatformBridge? platform, Uri? origin})
    : client = client ?? http.Client(),
      platform = platform ?? PlatformBridge(),
      origin =
          origin ??
          Uri.parse(
            kIsWeb
                ? Uri.base.origin
                : const String.fromEnvironment(
                    'API_ORIGIN',
                    defaultValue: 'https://35.212.249.154',
                  ),
          );
  final http.Client client;
  final PlatformBridge platform;
  final Uri origin;
  String? _token;
  bool _addressPicking = false;
  bool _addressCancelled = false;
  Future<void>? _authenticating;
  bool _closed = false;
  Map<String, dynamic> config = {};
  final _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;
  StreamSubscription<void>? _platformEvents;
  http.Client? _streamClient;

  Future<void> start() async {
    await authenticate();
    config = await request('GET', '/api/config') as Map<String, dynamic>;
    _platformEvents = platform.changes.listen((_) => _changes.add(null));
    if (kIsWeb) {
      platform.startEvents(origin.toString());
    } else {
      unawaited(_events());
    }
  }

  Future<void> authenticate() {
    return _authenticating ??= _authenticate().whenComplete(
      () => _authenticating = null,
    );
  }

  Future<void> _authenticate() async {
    final identity = await platform.identity();
    final challenge = await request(
      'POST',
      '/api/auth/challenge',
      body: identity,
      authenticated: false,
    ) as Map;
    final signature = await platform.sign(challenge['payload'] as String);
    final result = await request(
      'POST',
      '/api/auth/verify',
      body: {'id': challenge['id'], 'signature': signature},
      authenticated: false,
    ) as Map;
    _token = result['token'] as String?;
    if (kIsWeb && _platformEvents != null) {
      platform.startEvents(origin.toString());
    }
  }

  Future<dynamic> request(
    String method,
    String path, {
    Object? body,
    bool authenticated = true,
    bool retry = true,
  }) async {
    final req = http.Request(method, origin.resolve(path));
    req.headers['Accept'] = 'application/json';
    if (_token != null) req.headers['Authorization'] = 'Bearer $_token';
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    http.Response response;
    try {
      response = await http.Response.fromStream(await client.send(req))
          .timeout(const Duration(seconds: 40));
    } catch (_) {
      throw StateError('서버에 연결하지 못했어요. 인터넷 연결을 확인해주세요.');
    }
    if (response.statusCode == 401 && authenticated && retry) {
      await authenticate();
      return request(method, path, body: body, retry: false);
    }
    if (response.statusCode == 204) return null;
    final dynamic data;
    try {
      data = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      throw StateError('서버 응답을 확인하지 못했어요.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        data is Map
            ? (data['message'] as String? ?? '요청에 실패했어요.')
            : '요청에 실패했어요.',
      );
    }
    return data;
  }

  static String requestId() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Future<void> _events() async {
    while (!_closed) {
      try {
        _streamClient = http.Client();
        final req = http.Request('GET', origin.resolve('/api/events'));
        req.headers['Authorization'] = 'Bearer $_token';
        final response = await _streamClient!.send(req);
        if (response.statusCode == 401) {
          await authenticate();
        } else if (response.statusCode == 200) {
          await for (final line
              in response.stream
                  .transform(utf8.decoder)
                  .transform(const LineSplitter())) {
            if (_closed) break;
            if (line == 'event: changed') _changes.add(null);
          }
        }
      } catch (_) {
        /* Foreground refresh remains available during reconnection. */
      } finally {
        _streamClient?.close();
      }
      if (!_closed) await Future<void>.delayed(const Duration(seconds: 3));
    }
  }

  Future<String?> pickAddress() async {
    if (_addressPicking) throw StateError('주소 검색창을 먼저 닫아주세요.');
    _addressPicking = true;
    _addressCancelled = false;
    Map<String, dynamic>? launch;
    var popupClosed = false;
    Object? popupError;
    try {
      // Open the browser window synchronously inside the original tap gesture.
      platform.prepareAddressPopup();
      launch = await request(
        'POST',
        '/api/address-popup',
        body: <String, dynamic>{},
      ) as Map<String, dynamic>;
      if (_addressCancelled || _closed) return null;
      unawaited(
        platform
            .addressPopup(launch)
            .then(
              (_) {
                popupClosed = true;
              },
              onError: (Object error, StackTrace _) {
                popupError = error;
                popupClosed = true;
              },
            ),
      );
      final deadline = DateTime.now().add(const Duration(minutes: 10));
      while (!_closed &&
          !_addressCancelled &&
          DateTime.now().isBefore(deadline)) {
        // Polling also works when a mobile browser cannot retain window.opener.
        final status =
            await request('GET', '/api/address-popup/${launch['id']}') as Map;
        if (status['ready'] == true) {
          final address = (status['address'] as Map)['roadAddress'] as String;
          if (address.trim().isEmpty || address.runes.length > 120) {
            throw StateError('선택한 주소를 확인해주세요.');
          }
          return address;
        }
        if (popupError != null) throw StateError('주소 검색창을 열지 못했어요. 다시 시도해주세요.');
        if (popupClosed) return null;
        await Future<void>.delayed(const Duration(milliseconds: 1500));
      }
      if (_addressCancelled || _closed) return null;
      throw StateError('주소 검색 시간이 지났어요. 다시 검색해주세요.');
    } finally {
      try {
        await platform.cancelAddressPopup();
      } catch (_) {
        /* Closing an already detached popup is harmless. */
      }
      if (launch != null && !_closed) {
        try {
          await request(
            'DELETE',
            '/api/address-popup/${launch['id']}',
          ).timeout(const Duration(seconds: 5));
        } catch (_) {
          /* Expiry also removes abandoned results. */
        }
      }
      _addressPicking = false;
    }
  }

  Future<void> cancelAddressSearch() async {
    _addressCancelled = true;
    await platform.cancelAddressPopup();
  }

  Future<Map<String, dynamic>> notificationStatus({
    bool requestPermission = false,
  }) async {
    final status = await platform.notifications(
      config['webPushPublicKey'] as String? ?? '',
      request: requestPermission,
    );
    final kind = status['kind'];
    final payload = status['payload'];
    if (status['enabled'] == true && kind != null && payload != null) {
      await request(
        'PUT',
        '/api/push',
        body: {'kind': kind, 'payload': payload},
      );
    }
    return status;
  }

  Future<void> disableNotifications() async {
    await request('DELETE', '/api/push/${kIsWeb ? 'web' : 'android'}');
    await platform.disableNotifications();
  }

  void dispose() {
    _closed = true;
    _streamClient?.close();
    unawaited(_platformEvents?.cancel());
    client.close();
    platform.dispose();
    unawaited(_changes.close());
  }
}
