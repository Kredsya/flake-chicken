import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('flakePlatform')
external JSObject get _platform;

class PlatformBridge {
  final _changes = StreamController<void>.broadcast();
  PlatformBridge() {
    _platform.callMethod<JSAny?>(
      'listen'.toJS,
      (() => _changes.add(null)).toJS,
    );
  }
  Stream<void> get changes => _changes.stream;
  Future<dynamic> _call(String method, [Object? args]) async {
    final promise = _platform.callMethod<JSPromise<JSAny?>>(
      method.toJS,
      args.jsify(),
    );
    return (await promise.toDart).dartify();
  }

  Future<Map<String, dynamic>> identity() async =>
      Map<String, dynamic>.from(await _call('identity') as Map);
  Future<String> sign(String payload) async =>
      await _call('sign', payload) as String;
  Future<Map<String, dynamic>> notifications(
    String publicKey, {
    bool request = false,
  }) async => Map<String, dynamic>.from(
    await _call('notifications', {'publicKey': publicKey, 'request': request})
        as Map,
  );
  Future<void> disableNotifications() async {
    await _call('disableNotifications');
  }

  Future<void> openUrl(String url) async {
    await _call('openUrl', url);
  }

  void startEvents(String origin) {
    _platform.callMethod<JSAny?>('startEvents'.toJS, origin.toJS);
  }

  void dispose() {
    _platform.callMethod<JSAny?>('dispose'.toJS);
    unawaited(_changes.close());
  }
}
