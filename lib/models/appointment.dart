import 'package:flutter/foundation.dart';

@immutable
class ProfileSettings {
  ProfileSettings({
    required List<String> names,
    required List<String> addresses,
    this.gmgMode = false,
  }) : names = List.unmodifiable(names),
       addresses = List.unmodifiable(addresses) {
    if (names.length != 3 || addresses.length != 3) {
      throw ArgumentError('이름과 출발 주소는 각각 3칸이어야 합니다.');
    }
  }

  final List<String> names;
  final List<String> addresses;
  final bool gmgMode;

  Map<String, dynamic> toJson() => {
    'names': names,
    'addresses': addresses,
    'gmgMode': gmgMode,
  };

  factory ProfileSettings.fromJson(Map<String, dynamic> json) =>
      ProfileSettings(
        names: List<String>.from(json['names'] as List),
        addresses: List<String>.from(json['addresses'] as List),
        gmgMode: json['gmgMode'] as bool? ?? false,
      );
}

@immutable
class Appointment {
  const Appointment({
    required this.id,
    required this.title,
    required this.startsAt,
    required this.destination,
    required this.invitationCode,
    required this.displayName,
    required this.origin,
    this.participantCount = 1,
    this.isOwner = true,
    this.myChoice = false,
    this.isCancelled = false,
    this.isArchived = false,
    this.routeVariant = 0,
    this.durationMinutes,
    this.version = 1,
    this.connected = false,
    this.mapImage,
    this.routeMessage,
  });

  final String id;
  final String title;
  final DateTime startsAt;
  final String destination;
  final String invitationCode;
  final String displayName;
  final String origin;
  final int participantCount;
  final bool isOwner;
  final bool myChoice;
  final bool isCancelled;
  final bool isArchived;
  bool get isCompleted => !isCancelled && !startsAt.isAfter(DateTime.now());
  final int routeVariant;
  final int? durationMinutes;
  final int version;
  final bool connected;
  final Uint8List? mapImage;
  final String? routeMessage;

  Appointment copyWith({
    String? title,
    DateTime? startsAt,
    String? destination,
    String? displayName,
    String? origin,
    int? participantCount,
    bool? isOwner,
    bool? myChoice,
    bool? isCancelled,
    bool? isArchived,
    bool clearDuration = false,
    int? version,
    int? durationMinutes,
    Uint8List? mapImage,
    String? routeMessage,
  }) => Appointment(
    id: id,
    title: title ?? this.title,
    startsAt: startsAt ?? this.startsAt,
    destination: destination ?? this.destination,
    invitationCode: invitationCode,
    displayName: displayName ?? this.displayName,
    origin: origin ?? this.origin,
    participantCount: participantCount ?? this.participantCount,
    isOwner: isOwner ?? this.isOwner,
    myChoice: myChoice ?? this.myChoice,
    isCancelled: isCancelled ?? this.isCancelled,
    isArchived: isArchived ?? this.isArchived,
    routeVariant: routeVariant,
    durationMinutes: clearDuration
        ? null
        : (durationMinutes ?? this.durationMinutes),
    version: version ?? this.version,
    connected: connected,
    mapImage: clearDuration ? null : (mapImage ?? this.mapImage),
    routeMessage: routeMessage ?? this.routeMessage,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'startsAt': startsAt.toIso8601String(),
    'destination': destination,
    'invitationCode': invitationCode,
    'displayName': displayName,
    'origin': origin,
    'participantCount': participantCount,
    'isOwner': isOwner,
    'myChoice': myChoice,
    'isCancelled': isCancelled,
    'isArchived': isArchived,
    'routeVariant': routeVariant,
    'durationMinutes': durationMinutes,
    'version': version,
  };

  factory Appointment.fromJson(
    Map<String, dynamic> json, {
    bool connected = false,
  }) => Appointment(
    id: json['id'] as String,
    title: json['title'] as String,
    startsAt: DateTime.parse(json['startsAt'] as String).toLocal(),
    destination: json['destination'] as String,
    invitationCode: json['invitationCode'] as String,
    displayName: json['displayName'] as String,
    origin: json['origin'] as String,
    participantCount: json['participantCount'] as int,
    isOwner: json['isOwner'] as bool,
    myChoice: json['myChoice'] as bool,
    isCancelled: json['isCancelled'] as bool,
    isArchived: json['isArchived'] as bool? ?? false,
    routeVariant: json['routeVariant'] as int,
    durationMinutes: json['durationMinutes'] as int?,
    version: json['version'] as int? ?? 1,
    connected: connected,
  );
}
