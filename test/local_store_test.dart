import 'dart:convert';

import 'package:flake_chicken/data/local_store.dart';
import 'package:flake_chicken/models/appointment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 7);

  test(
    'independent profile choices survive restart as appointment snapshots',
    () async {
      final storage = MemoryStorage();
      final store = await AppStore.load(storage, now: now);
      final created = await store.createAppointment(
        title: '새 약속',
        startsAt: now.add(const Duration(days: 10)),
        destination: '서울역',
        nameIndex: 2,
        addressIndex: 1,
      );
      expect(created.displayName, '지민');
      expect(created.origin, '서울 강남구 테헤란로 25');
      expect(created.durationMinutes, isNull);
      await store.saveProfiles(
        ProfileSettings(
          names: ['새 이름', '다른 이름', '수정한 이름'],
          addresses: ['새 주소 1', '새 주소 2', '새 주소 3'],
        ),
      );
      final restored = await AppStore.load(storage, now: now);
      final snapshot = restored.appointments.firstWhere(
        (a) => a.id == created.id,
      );
      expect(snapshot.displayName, '지민');
      expect(snapshot.origin, '서울 강남구 테헤란로 25');
      expect(restored.profiles.names[2], '수정한 이름');
    },
  );

  test(
    'GMG is a future default and does not change existing choices',
    () async {
      final store = await AppStore.load(MemoryStorage(), now: now);
      final before = store.appointments.first;
      await store.saveProfiles(
        ProfileSettings(
          names: store.profiles.names,
          addresses: store.profiles.addresses,
          gmgMode: true,
        ),
      );
      expect(store.appointments.first.myChoice, before.myChoice);
      final created = await store.createAppointment(
        title: 'GMG 약속',
        startsAt: now.add(const Duration(days: 20)),
        destination: '강남역',
        nameIndex: 0,
        addressIndex: 2,
      );
      final joined = await store.joinAppointment('f7k2 m9q4', 1, 0);
      expect(created.myChoice, isTrue);
      expect(joined.myChoice, isTrue);
      expect(joined.isOwner, isFalse);
      expect(joined.participantCount, 4);
      expect(joined.displayName, '도윤');
      expect(joined.origin, store.profiles.addresses.first);
    },
  );

  test(
    'only creators can edit, and final cancellations cannot be changed',
    () async {
      final store = await AppStore.load(MemoryStorage(), now: now);
      final guest = store.appointments.firstWhere((a) => !a.isOwner);
      final cancelled = store.appointments.firstWhere((a) => a.isCancelled);
      for (final appointment in [guest, cancelled]) {
        await expectLater(
          store.updateAppointment(
            id: appointment.id,
            title: '변경 시도',
            startsAt: now,
            destination: '서울역',
          ),
          throwsStateError,
        );
      }
      await expectLater(
        store.setMyChoice(cancelled.id, false),
        throwsStateError,
      );
      expect(
        store.appointments.firstWhere((a) => a.id == cancelled.id).isCancelled,
        isTrue,
      );
    },
  );

  test(
    'only known invitations can be joined and duplicate joining is rejected',
    () async {
      final store = await AppStore.load(MemoryStorage(), now: now);
      expect(() => store.previewInvitation('UNKNOWN8'), throwsStateError);
      await store.joinAppointment('F7K2M9Q4', 0, 0);
      await expectLater(
        store.joinAppointment('F7K2M9Q4', 1, 1),
        throwsStateError,
      );
      expect(
        store.appointments.where((a) => a.invitationCode == 'F7K2M9Q4'),
        hasLength(1),
      );
    },
  );

  test(
    'only cancelled appointments can be deleted and removal survives restart',
    () async {
      final storage = MemoryStorage();
      final store = await AppStore.load(storage, now: now);
      final active = store.appointments.firstWhere((a) => !a.isCancelled);
      final cancelled = store.appointments.firstWhere((a) => a.isCancelled);
      await expectLater(
        store.deleteCancelledAppointment(active.id),
        throwsStateError,
      );
      expect(store.appointments, hasLength(3));
      await store.deleteCancelledAppointment(cancelled.id);
      expect(store.appointments, hasLength(2));
      final restored = await AppStore.load(storage, now: now);
      expect(restored.appointments.any((a) => a.id == cancelled.id), isFalse);
      expect(restored.appointments.any((a) => a.id == active.id), isTrue);
    },
  );

  test('concurrent local choices are serialized and persisted without losing either', () async {
    final storage = MemoryStorage();
    final store = await AppStore.load(storage, now: now);
    final active = store.appointments.where((a) => !a.isCancelled).toList();
    await Future.wait(active.map((a) => store.setMyChoice(a.id, true)));
    final restored = await AppStore.load(storage, now: now);
    expect(
      restored.appointments
          .where((a) => !a.isCancelled)
          .every((a) => a.myChoice),
      isTrue,
    );
    // The UI preview has no remote participant votes to expose or infer.
    final serialized = jsonDecode(storage.value!) as Map<String, dynamic>;
    expect(
      (serialized['appointments'] as List).first,
      isNot(contains('otherVotes')),
    );
  });

  test(
    'failed persistence rolls back and the next write still works',
    () async {
      final storage = _FailOnceStorage();
      final store = await AppStore.load(storage, now: now);
      final appointment = store.appointments.first;
      await expectLater(
        store.setMyChoice(appointment.id, true),
        throwsStateError,
      );
      expect(store.appointments.first.myChoice, isFalse);
      await store.setMyChoice(appointment.id, true);
      expect(store.appointments.first.myChoice, isTrue);
    },
  );

  test('editing a location clears the sample duration but preserves profile snapshot', () async {
    final store = await AppStore.load(MemoryStorage(), now: now);
    final appointment = store.appointments.first;
    await store.updateAppointment(
      id: appointment.id,
      title: '장소 변경',
      startsAt: appointment.startsAt,
      destination: '서울역',
    );
    final edited = store.appointments.firstWhere((a) => a.id == appointment.id);
    expect(edited.durationMinutes, isNull);
    expect(edited.displayName, appointment.displayName);
    expect(edited.origin, appointment.origin);
    expect(edited.invitationCode, appointment.invitationCode);
  });
}

class _FailOnceStorage extends MemoryStorage {
  bool _fail = true;

  @override
  Future<void> write(String value) async {
    if (_fail) {
      _fail = false;
      throw StateError('storage unavailable');
    }
    await super.write(value);
  }
}
