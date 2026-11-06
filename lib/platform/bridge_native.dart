import 'package:flutter/services.dart';

class PlatformBridge {
  static const _channel = MethodChannel('dev.flakechicken/platform');
  static const _events = EventChannel('dev.flakechicken/events');
  Stream<void> get changes => _events.receiveBroadcastStream().map((_) {});
  Future<Map<String, dynamic>> identity() async => Map<String, dynamic>.from(
    (await _channel.invokeMapMethod<String, dynamic>('identity'))!,
  );
  Future<String> sign(String payload) async =>
      (await _channel.invokeMethod<String>('sign', payload))!;
  Future<Map<String, dynamic>> notifications(
    String publicKey, {
    bool request = false,
  }) async => Map<String, dynamic>.from(
    (await _channel.invokeMapMethod<String, dynamic>('notifications', {
      'request': request,
    }))!,
  );
  Future<void> disableNotifications() async =>
      _channel.invokeMethod('disableNotifications');
  Future<void> openUrl(String url) async =>
      _channel.invokeMethod('openUrl', url);
  void startEvents(String origin) {}
  void dispose() {}
}
