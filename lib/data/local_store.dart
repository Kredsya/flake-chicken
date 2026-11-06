import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/widgets.dart';

import 'backend_api.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/appointment.dart';

abstract interface class AppStorage {
  Future<String?> read();
  Future<void> write(String value);
}

class PreferencesStorage implements AppStorage {
  final _preferences = SharedPreferencesAsync();
  // ignore: prefer_initializing_formals
  PreferencesStorage({String key = 'flake_chicken.ui.v1'}) : _key = key;
  final String _key;

  @override
  Future<String?> read() => _preferences.getString(_key);

  @override
  Future<void> write(String value) => _preferences.setString(_key, value);
}

class MemoryStorage implements AppStorage {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async => this.value = value;
}

/// Production uses connect(); load() supplies isolated offline design fixtures.
class AppStore extends ChangeNotifier with WidgetsBindingObserver {
  AppStore._(
    this._storage,
    this._profiles,
    this._appointments,
    this._invitations,
  );

  BackendApi? _api;
  Timer? _poll;
  StreamSubscription<void>? _events;
  Future<void>? _refreshing;
  bool _active = true;
  bool _disposed = false;
  bool _loadingRoutes = false;
  final _routeAttempts = <String, DateTime>{};
  String? connectionError;
  bool get connected => _api != null;
  bool get profilesReady =>
      _profiles.names.any((s) => s.trim().isNotEmpty) &&
      _profiles.addresses.any((s) => s.trim().isNotEmpty);
  final AppStorage _storage;
  ProfileSettings _profiles;
  List<Appointment> _appointments;
  final List<Appointment> _invitations;
  Future<void> _writes = Future.value();
  Set<String> _celebratedCancellationIds = {};

  bool get hasUnseenCancellation => _appointments.any(
    (a) => a.isCancelled && !_celebratedCancellationIds.contains(a.id),
  );

  // Persist before drawing so reconnects and process restarts cannot replay it.
  Future<bool> claimCancellationCelebration() {
    if (!hasUnseenCancellation) return Future.value(false);
    return _commit(() {
      final unseen = _appointments
          .where(
            (a) => a.isCancelled && !_celebratedCancellationIds.contains(a.id),
          )
          .map((a) => a.id)
          .toSet();
      if (unseen.isEmpty) return false;
      _celebratedCancellationIds = {..._celebratedCancellationIds, ...unseen};
      return true;
    });
  }

  ProfileSettings get profiles => _profiles;
  List<Appointment> get appointments {
    final sorted = _appointments.where((a) => !a.isArchived).toList();
    sorted.sort((a, b) {
      if (a.isCancelled != b.isCancelled) return a.isCancelled ? 1 : -1;
      return a.startsAt.compareTo(b.startsAt);
    });
    return List.unmodifiable(sorted);
  }

  List<Appointment> get hallOfFame {
    final items =
        _appointments.where((a) => a.isArchived && !a.isCancelled).toList()
          ..sort((a, b) => b.startsAt.compareTo(a.startsAt));
    return List.unmodifiable(items);
  }

  Future<void> archiveAppointment(String id) async {
    if (connected) {
      await _api!.request(
        'POST',
        '/api/appointments/$id/hall-of-fame',
        body: <String, dynamic>{},
      );
      await refresh(force: true);
      return;
    }
    return _commit(() {
      final a = _appointments.firstWhere((a) => a.id == id);
      if (!a.isCompleted) throw StateError('시간이 지난 약속만 옮길 수 있어요.');
      _appointments = _appointments
          .map((a) => a.id == id ? a.copyWith(isArchived: true) : a)
          .toList();
    });
  }

  static Future<AppStore> connect(AppStorage storage, {BackendApi? api}) async {
    final raw = await storage.read();
    final profiles = raw == null
        ? ProfileSettings(names: ['', '', ''], addresses: ['', '', ''])
        : ProfileSettings.fromJson(
            (jsonDecode(raw) as Map)['profiles'] as Map<String, dynamic>,
          );
    final store = AppStore._(storage, profiles, [], []);
    if (raw != null) {
      store._celebratedCancellationIds = Set<String>.from(
        (jsonDecode(raw) as Map)['celebratedCancellationIds'] as List? ?? [],
      );
    }
    store._api = api ?? BackendApi();
    try {
      await store._api!.start();
      await store.refresh();
      store._events = store._api!.changes.listen(
        (_) => unawaited(store.refresh()),
      );
      store._poll = Timer.periodic(const Duration(seconds: 30), (_) {
        if (store._active) unawaited(store.refresh());
      });
      WidgetsBinding.instance.addObserver(store);
      unawaited(
        store.notificationStatus().catchError((_) => <String, dynamic>{}),
      );
      return store;
    } catch (_) {
      store.dispose();
      rethrow;
    }
  }

  Future<void> refresh({bool force = false}) async {
    if (force && _refreshing != null) await _refreshing;
    return _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  }

  Future<void> _refresh() async {
    if (_api == null || _disposed) return;
    try {
      final data = await _api!.request('GET', '/api/appointments') as Map;
      if (_disposed) return;
      _appointments = (data['appointments'] as List).map((item) {
        var next = Appointment.fromJson(
          item as Map<String, dynamic>,
          connected: true,
        );
        final old = _appointments.where((a) => a.id == next.id).firstOrNull;
        if (old != null &&
            old.startsAt == next.startsAt &&
            old.destination == next.destination &&
            old.origin == next.origin) {
          next = next.copyWith(
            mapImage: old.mapImage,
            durationMinutes: old.durationMinutes,
            routeMessage: old.routeMessage,
          );
        }
        return next;
      }).toList();
      connectionError = null;
      notifyListeners();
      unawaited(_loadRoutes());
    } catch (_) {
      if (_disposed) return;
      connectionError = '연결을 확인해주세요. 아래로 당겨 다시 불러올 수 있어요.';
      notifyListeners();
      // Initial load must not silently masquerade as an empty account.
      if (_poll == null) rethrow;
    }
  }

  String _routeKey(Appointment a) =>
      '${a.id}:${a.startsAt.toUtc()}:${a.destination}:${a.origin}';
  Future<void> _loadRoutes() async {
    if (_loadingRoutes || _api == null) return;
    _loadingRoutes = true;
    try {
      // Sequential requests keep the small VM and provider quotas predictable.
      for (final snapshot in List<Appointment>.of(_appointments)) {
        if (_disposed || !_active) break;
        if (snapshot.mapImage != null || snapshot.isArchived) continue;
        final key = _routeKey(snapshot);
        final attempted = _routeAttempts[key];
        if (attempted != null &&
            DateTime.now().difference(attempted) <
                const Duration(minutes: 30)) {
          continue;
        }
        _routeAttempts[key] = DateTime.now();
        try {
          final data = await _api!.request(
            'GET',
            '/api/appointments/${snapshot.id}/route',
          ) as Map;
          if (_disposed) return;
          final current = _appointments
              .where((a) => a.id == snapshot.id)
              .firstOrNull;
          if (current == null || _routeKey(current) != key) continue;
          _appointments = _appointments
              .map(
                (a) => a.id == current.id
                    ? a.copyWith(
                        mapImage: base64Decode(data['mapBase64'] as String),
                        durationMinutes: data['durationMinutes'] as int,
                      )
                    : a,
              )
              .toList();
        } on StateError catch (error) {
          if (_disposed) return;
          _appointments = _appointments
              .map(
                (a) => a.id == snapshot.id && _routeKey(a) == key
                    ? a.copyWith(routeMessage: error.message)
                    : a,
              )
              .toList();
        } catch (_) {
          /* Map availability does not prevent managing appointments. */
        }
        if (!_disposed) notifyListeners();
        // At most twelve billable route pairs per minute per foreground client.
        await Future<void>.delayed(const Duration(seconds: 5));
      }
    } finally {
      _loadingRoutes = false;
    }
  }

  Future<String?> pickAddress() {
    if (_api == null) throw StateError('주소 검색은 서버 연결이 필요해요.');
    return _api!.pickAddress();
  }

  Future<void> cancelAddressSearch() async => _api?.cancelAddressSearch();

  Future<Map<String, dynamic>> notificationStatus({
    bool requestPermission = false,
  }) async => _api == null
      ? {'supported': false, 'enabled': false}
      : _api!.notificationStatus(requestPermission: requestPermission);
  Future<void> disableNotifications() async => _api?.disableNotifications();
  Future<void> openPolicy(String page) async =>
      _api?.platform.openUrl(_api!.origin.resolve('/$page.html').toString());

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    if (_active && !_disposed) {
      unawaited(refresh());
      unawaited(notificationStatus().catchError((_) => <String, dynamic>{}));
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    unawaited(_events?.cancel());
    WidgetsBinding.instance.removeObserver(this);
    _api?.dispose();
    super.dispose();
  }

  static Future<AppStore> load(AppStorage storage, {DateTime? now}) async {
    final base = now ?? DateTime.now();
    final profiles = ProfileSettings(
      names: ['민수', '도윤', '지민'],
      addresses: ['서울 마포구 월드컵로 12', '서울 강남구 테헤란로 25', '서울 성북구 안암로 145'],
    );
    final nextSaturday = DateTime(
      base.year,
      base.month,
      base.day + ((DateTime.saturday - base.weekday + 6) % 7) + 1,
      19,
    );
    final samples = [
      Appointment(
        id: 'sample-dinner',
        title: '성수에서 저녁',
        startsAt: nextSaturday,
        destination: '서울 성동구 성수이로 18',
        invitationCode: 'K4N7P2Q8',
        displayName: profiles.names.first,
        origin: profiles.addresses.first,
        participantCount: 4,
        durationMinutes: 38,
      ),
      Appointment(
        id: 'sample-boardgame',
        title: '퇴근 후 보드게임',
        startsAt: nextSaturday.add(const Duration(days: 4, hours: 1)),
        destination: '홍대입구역',
        invitationCode: 'B7R3M8T2',
        displayName: profiles.names.first,
        origin: profiles.addresses.first,
        participantCount: 5,
        durationMinutes: 52,
        routeVariant: 1,
        isOwner: false,
      ),
      Appointment(
        id: 'sample-walk',
        title: '한강 산책',
        startsAt: nextSaturday.add(const Duration(days: 8, hours: -5)),
        destination: '뚝섬한강공원',
        invitationCode: 'H6W9S3V7',
        displayName: profiles.names.first,
        origin: profiles.addresses.first,
        participantCount: 3,
        durationMinutes: 31,
        routeVariant: 2,
        myChoice: true,
        isCancelled: true,
      ),
    ];
    final invitations = [
      Appointment(
        id: 'sample-invitation',
        title: '성수에서 저녁',
        startsAt: nextSaturday,
        destination: '서울 성동구 성수이로 18',
        invitationCode: 'F7K2M9Q4',
        displayName: '',
        origin: '',
        participantCount: 3,
        isOwner: false,
        durationMinutes: 38,
      ),
    ];
    final raw = await storage.read();
    if (raw != null) {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return AppStore._(
          storage,
          ProfileSettings.fromJson(json['profiles'] as Map<String, dynamic>),
          (json['appointments'] as List)
              .map((item) => Appointment.fromJson(item as Map<String, dynamic>))
              .toList(),
          invitations,
        )
        .._celebratedCancellationIds = Set<String>.from(
          json['celebratedCancellationIds'] as List? ?? [],
        );
    }
    return AppStore._(storage, profiles, samples, invitations)
      // Design fixtures are not real cancellation events.
      .._celebratedCancellationIds = samples
          .where((a) => a.isCancelled)
          .map((a) => a.id)
          .toSet();
  }

  Future<T> _commit<T>(T Function() mutate) {
    final result = Completer<T>();
    _writes = _writes.then((_) async {
      final previousProfiles = _profiles;
      final previousAppointments = _appointments;
      final previousCelebrations = _celebratedCancellationIds;
      try {
        // Preserve acknowledgements written by another open browser tab.
        final latest = await _storage.read();
        if (latest != null) {
          _celebratedCancellationIds = {
            ..._celebratedCancellationIds,
            ...List<String>.from(
              (jsonDecode(latest) as Map)['celebratedCancellationIds']
                      as List? ??
                  [],
            ),
          };
        }
        final value = mutate();
        await _storage.write(
          jsonEncode({
            'version': 1,
            'profiles': _profiles.toJson(),
            'celebratedCancellationIds': _celebratedCancellationIds.toList(),
            if (!connected)
              'appointments': _appointments
                  .map((item) => item.toJson())
                  .toList(),
          }),
        );
        notifyListeners();
        result.complete(value);
      } catch (error, stack) {
        _profiles = previousProfiles;
        _appointments = previousAppointments;
        _celebratedCancellationIds = previousCelebrations;
        result.completeError(error, stack);
      }
    });
    return result.future;
  }

  Future<void> saveProfiles(ProfileSettings profiles) => _commit(() {
    if (!connected &&
        (!profiles.names.any((name) => name.trim().isNotEmpty) ||
            !profiles.addresses.any((address) => address.trim().isNotEmpty))) {
      throw ArgumentError('이름과 출발 주소를 하나 이상 입력해주세요.');
    }
    _profiles = profiles;
  });

  Future<void> deleteOwnedAppointment(String id) async {
    if (connected) {
      await _api!.request('DELETE', '/api/appointments/$id/owned');
      await refresh(force: true);
      return;
    }
    return _commit(() {
      final a = _appointments.firstWhere((a) => a.id == id);
      if (!a.isOwner || a.isCancelled || a.isCompleted) {
        throw StateError('이 약속은 삭제할 수 없어요.');
      }
      _appointments = _appointments.where((a) => a.id != id).toList();
    });
  }

  Future<void> deleteCancelledAppointment(String id) async {
    if (connected) {
      await _api!.request('DELETE', '/api/appointments/$id');
      await refresh(force: true);
      return;
    }
    return _commit(() {
      final appointment = _appointments.firstWhere((item) => item.id == id);
      if (!appointment.isCancelled && !appointment.isArchived) {
        throw StateError('파토난 약속이나 명예의 전당의 약속만 삭제할 수 있어요.');
      }
      _appointments = _appointments.where((item) => item.id != id).toList();
    });
  }

  (String, String) _selection(int nameIndex, int addressIndex) {
    final name = _profiles.names[nameIndex].trim();
    final address = _profiles.addresses[addressIndex].trim();
    if (name.isEmpty || address.isEmpty) {
      throw ArgumentError('표시 이름과 출발 주소를 선택해주세요.');
    }
    return (name, address);
  }

  Future<Appointment> createAppointment({
    required String title,
    required DateTime startsAt,
    required String destination,
    required int nameIndex,
    required int addressIndex,
  }) async {
    if (connected) {
      final (name, address) = _selection(nameIndex, addressIndex);
      final data = await _api!.request(
        'POST',
        '/api/appointments',
        body: {
          'title': title.trim(),
          'startsAt': startsAt.toUtc().toIso8601String(),
          'destination': destination.trim(),
          'displayName': name,
          'origin': address,
          'choice': profiles.gmgMode,
          'requestId': BackendApi.requestId(),
        },
      );
      final result = Appointment.fromJson(
        data as Map<String, dynamic>,
        connected: true,
      );
      await refresh(force: true);
      return result;
    }
    return _commit(() {
      _validate(title, destination);
      final (name, address) = _selection(nameIndex, addressIndex);
      const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
      final random = Random.secure();
      String code;
      do {
        code = List.generate(
          8,
          (_) => alphabet[random.nextInt(alphabet.length)],
        ).join();
      } while ([
        ..._appointments,
        ..._invitations,
      ].any((a) => a.invitationCode == code));
      final appointment = Appointment(
        id: code,
        title: title.trim(),
        startsAt: startsAt,
        destination: destination.trim(),
        invitationCode: code,
        displayName: name,
        origin: address,
        myChoice: _profiles.gmgMode,
        routeVariant: _appointments.length % 3,
      );
      _appointments = [..._appointments, appointment];
      return appointment;
    });
  }

  Future<void> updateAppointment({
    required String id,
    required String title,
    required DateTime startsAt,
    required String destination,
  }) async {
    if (connected) {
      final current = _appointments.firstWhere((a) => a.id == id);
      await _api!.request(
        'PATCH',
        '/api/appointments/$id',
        body: {
          'title': title.trim(),
          'startsAt': startsAt.toUtc().toIso8601String(),
          'destination': destination.trim(),
          'version': current.version,
        },
      );
      await refresh(force: true);
      return;
    }
    return _commit(() {
      _validate(title, destination);
      final current = _appointments.firstWhere((a) => a.id == id);
      if (!current.isOwner || current.isCancelled || current.isCompleted) {
        throw StateError('이 약속은 수정할 수 없어요.');
      }
      _appointments = _appointments
          .map(
            (a) => a.id == id
                ? a.copyWith(
                    title: title.trim(),
                    startsAt: startsAt,
                    destination: destination.trim(),
                    clearDuration:
                        destination.trim() != a.destination ||
                        startsAt != a.startsAt,
                  )
                : a,
          )
          .toList();
    });
  }

  Future<void> setMyChoice(String id, bool value) async {
    if (connected) {
      await _api!.request(
        'PUT',
        '/api/appointments/$id/choice',
        body: {'choice': value},
      );
      await refresh(force: true);
      return;
    }
    return _commit(() {
      final current = _appointments.firstWhere((a) => a.id == id);
      if (current.isCancelled || current.isCompleted) {
        throw StateError('종료된 약속은 변경할 수 없어요.');
      }
      _appointments = _appointments
          .map((a) => a.id == id ? a.copyWith(myChoice: value) : a)
          .toList();
    });
  }

  static String normalizeCode(String code) =>
      code.replaceAll(RegExp(r'\s'), '').toUpperCase();

  FutureOr<Appointment> previewInvitation(String code) {
    if (connected) {
      return _api!
          .request(
            'GET',
            '/api/invitations/${Uri.encodeComponent(normalizeCode(code))}',
          )
          .then(
            (data) => Appointment.fromJson(
              data as Map<String, dynamic>,
              connected: true,
            ),
          );
    }
    final normalized = normalizeCode(code);
    if (_appointments.any((a) => a.invitationCode == normalized)) {
      throw StateError('이미 참여 중인 약속이에요.');
    }
    return _invitations.firstWhere(
      (a) => a.invitationCode == normalized && !a.isCancelled,
      orElse: () => throw StateError('초대 코드를 확인해주세요.'),
    );
  }

  Future<Appointment> joinAppointment(
    String code,
    int nameIndex,
    int addressIndex,
  ) async {
    if (connected) {
      final (name, address) = _selection(nameIndex, addressIndex);
      final data = await _api!.request(
        'POST',
        '/api/invitations/${Uri.encodeComponent(normalizeCode(code))}/join',
        body: {
          'displayName': name,
          'origin': address,
          'choice': profiles.gmgMode,
        },
      );
      await refresh(force: true);
      return Appointment.fromJson(
        data as Map<String, dynamic>,
        connected: true,
      );
    }
    return _commit(() {
      final invitation = previewInvitation(code) as Appointment;
      final (name, address) = _selection(nameIndex, addressIndex);
      final joined = invitation.copyWith(
        displayName: name,
        origin: address,
        participantCount: invitation.participantCount + 1,
        myChoice: _profiles.gmgMode,
      );
      _appointments = [..._appointments, joined];
      return joined;
    });
  }

  static void _validate(String title, String destination) {
    if (title.trim().isEmpty || destination.trim().isEmpty) {
      throw ArgumentError('약속 이름과 장소를 입력해주세요.');
    }
  }
}
