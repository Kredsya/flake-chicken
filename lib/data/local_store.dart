import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/appointment.dart';

abstract interface class AppStorage {
  Future<String?> read();
  Future<void> write(String value);
}

class PreferencesStorage implements AppStorage {
  final _preferences = SharedPreferencesAsync();
  static const _key = 'flake_chicken.ui.v1';

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

/// An offline UI repository. Routes, durations and invitations are sample data;
/// there is no server, remote vote state, push notification or Maps request.
class AppStore extends ChangeNotifier {
  AppStore._(
    this._storage,
    this._profiles,
    this._appointments,
    this._invitations,
  );

  final AppStorage _storage;
  ProfileSettings _profiles;
  List<Appointment> _appointments;
  final List<Appointment> _invitations;
  Future<void> _writes = Future.value();

  ProfileSettings get profiles => _profiles;
  List<Appointment> get appointments {
    final sorted = List<Appointment>.of(_appointments);
    sorted.sort((a, b) {
      if (a.isCancelled != b.isCancelled) return a.isCancelled ? 1 : -1;
      return a.startsAt.compareTo(b.startsAt);
    });
    return List.unmodifiable(sorted);
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
      );
    }
    return AppStore._(storage, profiles, samples, invitations);
  }

  Future<T> _commit<T>(T Function() mutate) {
    final result = Completer<T>();
    _writes = _writes.then((_) async {
      final previousProfiles = _profiles;
      final previousAppointments = _appointments;
      try {
        final value = mutate();
        await _storage.write(
          jsonEncode({
            'version': 1,
            'profiles': _profiles.toJson(),
            'appointments': _appointments.map((item) => item.toJson()).toList(),
          }),
        );
        notifyListeners();
        result.complete(value);
      } catch (error, stack) {
        _profiles = previousProfiles;
        _appointments = previousAppointments;
        result.completeError(error, stack);
      }
    });
    return result.future;
  }

  Future<void> saveProfiles(ProfileSettings profiles) => _commit(() {
    if (!profiles.names.any((name) => name.trim().isNotEmpty) ||
        !profiles.addresses.any((address) => address.trim().isNotEmpty)) {
      throw ArgumentError('이름과 출발 주소를 하나 이상 입력해주세요.');
    }
    _profiles = profiles;
  });

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
  }) => _commit(() {
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

  Future<void> updateAppointment({
    required String id,
    required String title,
    required DateTime startsAt,
    required String destination,
  }) => _commit(() {
    _validate(title, destination);
    final current = _appointments.firstWhere((a) => a.id == id);
    if (!current.isOwner || current.isCancelled) {
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

  Future<void> setMyChoice(String id, bool value) => _commit(() {
    final current = _appointments.firstWhere((a) => a.id == id);
    if (current.isCancelled) throw StateError('이미 파토난 약속이에요.');
    _appointments = _appointments
        .map((a) => a.id == id ? a.copyWith(myChoice: value) : a)
        .toList();
  });

  static String normalizeCode(String code) =>
      code.replaceAll(RegExp(r'\s'), '').toUpperCase();

  Appointment previewInvitation(String code) {
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
  ) => _commit(() {
    final invitation = previewInvitation(code);
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

  static void _validate(String title, String destination) {
    if (title.trim().isEmpty || destination.trim().isEmpty) {
      throw ArgumentError('약속 이름과 장소를 입력해주세요.');
    }
  }
}
