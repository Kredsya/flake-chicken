import 'dart:io';
import 'dart:ui' as ui;

import 'package:flake_chicken/data/local_store.dart';
import 'package:flake_chicken/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  _PreviewBinding();

  setUpAll(() async {
    final loader = FontLoader('NotoSansKR')
      ..addFont(rootBundle.load('assets/fonts/NotoSansKR.ttf'));
    await loader.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  Future<AppStore> launch(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    AppStorage? storage,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = await AppStore.load(
      storage ?? MemoryStorage(),
      now: DateTime(2026, 11, 7),
    );
    await tester.pumpWidget(FlakeChickenApp(store: store));
    await tester.pumpAndSettle();
    return store;
  }

  Future<void> menu(WidgetTester tester, String action) async {
    await tester.tap(find.byKey(const ValueKey('appointment-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('$action-menu-item')));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'map cards, action menu and private choice work without extra UI copy',
    (tester) async {
      final store = await launch(tester);
      expect(find.text('언제 한 번 밥 먹자'), findsOneWidget);
      expect(find.text('그래그래 연락 한 번 할게'), findsOneWidget);
      expect(find.text('우리의 약속'), findsNothing);
      expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
      expect(find.text('성수에서 저녁'), findsOneWidget);
      expect(find.text('파 토'), findsOneWidget);
      expect(find.text('Google Maps'), findsNothing);
      expect(find.text('코드로 참여'), findsNothing);
      expect(find.byIcon(Icons.share), findsNothing);
      await capture(tester, '01-home');

      await tester.tap(find.byKey(const ValueKey('appointment-menu')));
      await tester.pumpAndSettle();
      expect(find.text('새 약속'), findsOneWidget);
      expect(find.text('코드로 참여'), findsOneWidget);
      await capture(tester, '02-menu');
      await tester.tap(find.byKey(const ValueKey('appointment-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('appointment-sample-dinner')));
      await tester.pumpAndSettle();
      expect(find.text('수정'), findsOneWidget);
      await capture(tester, '03-card-actions');
      await tester.tap(find.byKey(const ValueKey('vote-sample-dinner')));
      await tester.pumpAndSettle();
      expect(store.appointments.first.myChoice, isTrue);
      expect(store.appointments.first.isCancelled, isFalse);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'guest events have no edit action and cancelled events expose only delete',
    (tester) async {
      await launch(tester);
      await tester.tap(
        find.byKey(const ValueKey('appointment-sample-boardgame')),
      );
      await tester.pumpAndSettle();
      expect(find.text('수정'), findsNothing);
      expect(
        find.byKey(const ValueKey('vote-sample-boardgame')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('appointment-sample-walk')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('vote-sample-walk')), findsNothing);
      expect(find.text('파 토'), findsOneWidget);
      expect(find.text('수정'), findsNothing);
      expect(find.byKey(const ValueKey('delete-sample-walk')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('delete-sample-walk')));
      await tester.pumpAndSettle();
      expect(find.text('한강 산책'), findsNothing);
      expect(find.text('파 토'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'create validates fields and saves independent profile selections',
    (tester) async {
      final store = await launch(tester);
      await menu(tester, 'create');
      await tester.tap(find.text('약속 만들기'));
      await tester.pumpAndSettle();
      expect(find.text('약속 이름을 입력해주세요.'), findsOneWidget);
      expect(find.text('만날 장소를 입력해주세요.'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('appointment-title')),
        '성수에서 저녁',
      );
      await tester.enterText(
        find.byKey(const ValueKey('appointment-destination')),
        '서울 성동구 성수이로 18',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('name-choice-2')));
      await tester.tap(find.byKey(const ValueKey('name-choice-2')));
      await tester.ensureVisible(
        find.byKey(const ValueKey('address-choice-1')),
      );
      await tester.tap(find.byKey(const ValueKey('address-choice-1')));
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await capture(tester, '04-create');
      await tester.tap(find.text('약속 만들기'));
      await tester.pumpAndSettle();
      expect(store.appointments, hasLength(4));
      final created = store.appointments.firstWhere(
        (a) => a.id != 'sample-dinner' && a.title == '성수에서 저녁',
      );
      expect(created.displayName, '지민');
      expect(created.origin, '서울 강남구 테헤란로 25');
      expect(find.text('언제 한 번 밥 먹자'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'joining previews an invitation and rejects stale or duplicate code',
    (tester) async {
      final store = await launch(tester);
      await menu(tester, 'join');
      await tester.tap(find.byKey(const ValueKey('check-invitation')));
      await tester.pumpAndSettle();
      expect(find.text('초대 코드를 확인해주세요.'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('invitation-code')),
        'F7K2 M9Q4',
      );
      await tester.tap(find.byKey(const ValueKey('check-invitation')));
      await tester.pumpAndSettle();
      expect(find.text('현재 3명'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('name-choice-2')));
      await tester.tap(find.byKey(const ValueKey('name-choice-2')));
      await tester.ensureVisible(
        find.byKey(const ValueKey('address-choice-1')),
      );
      await tester.tap(find.byKey(const ValueKey('address-choice-1')));
      await tester.pumpAndSettle();
      await capture(tester, '05-join');
      await tester.enterText(
        find.byKey(const ValueKey('invitation-code')),
        'INVALID8',
      );
      await tester.pumpAndSettle();
      expect(find.text('현재 3명'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, '이 약속에 참여하기'),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(
        find.byKey(const ValueKey('invitation-code')),
        'F7K2M9Q4',
      );
      await tester.tap(find.byKey(const ValueKey('check-invitation')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('이 약속에 참여하기'));
      await tester.pumpAndSettle();
      final joined = store.appointments.firstWhere(
        (a) => a.id == 'sample-invitation',
      );
      expect(joined.displayName, '지민');
      expect(joined.origin, '서울 강남구 테헤란로 25');
      expect(joined.isOwner, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'settings and GMG autosave without changing existing appointment snapshots',
    (tester) async {
      final store = await launch(tester);
      final original = store.appointments.first;
      await tester.tap(find.byKey(const ValueKey('open-settings')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('profile-name-0')),
        '새 이름',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.ensureVisible(find.byKey(const ValueKey('gmg-mode-switch')));
      await tester.tap(find.byKey(const ValueKey('gmg-mode-switch')));
      await tester.pumpAndSettle();
      await capture(tester, '06-profile');
      expect(find.text('저장'), findsNothing);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(store.profiles.gmgMode, isTrue);
      expect(store.profiles.names.first, '새 이름');
      expect(store.appointments.first.displayName, original.displayName);
      expect(store.appointments.first.myChoice, original.myChoice);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'small phone and enlarged text stay within the available layout',
    (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await launch(tester, size: const Size(320, 720));
      await tester.tap(find.byKey(const ValueKey('appointment-menu')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('create-menu-item')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('address-choice-2')),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('creator can pick date and time, copy code, and save an edit', (
    tester,
  ) async {
    final store = await launch(tester);
    String? copiedCode;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedCode = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('appointment-sample-dinner')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('수정'));
    await tester.pumpAndSettle();
    expect(find.text('약속 수정'), findsOneWidget);
    expect(find.byKey(const ValueKey('name-choice-0')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('pick-date')));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('선택'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pick-time')));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    await tester.tap(find.text('선택'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('복사'));
    await tester.tap(find.text('복사'));
    await tester.pumpAndSettle();
    expect(find.text('복사됨'), findsOneWidget);
    expect(copiedCode, 'K4N7P2Q8');
    await tester.ensureVisible(find.byKey(const ValueKey('appointment-title')));
    await tester.enterText(
      find.byKey(const ValueKey('appointment-title')),
      '성수에서 저녁 모임',
    );
    await tester.tap(find.text('변경사항 저장'));
    await tester.pumpAndSettle();
    expect(store.appointments, hasLength(3));
    expect(store.appointments.first.title, '성수에서 저녁 모임');
    expect(store.appointments.first.displayName, '민수');
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings flush the last edit when leaving before the debounce', (
    tester,
  ) async {
    final storage = MemoryStorage();
    await launch(tester, storage: storage);
    await tester.tap(find.byKey(const ValueKey('open-settings')));
    await tester.pumpAndSettle();
    expect(find.text('환경설정'), findsOneWidget);
    expect(find.text('저장'), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('profile-name-1')),
      '바로 저장',
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('언제 한 번 밥 먹자'), findsOneWidget);
    final restored = await AppStore.load(storage);
    expect(restored.profiles.names[1], '바로 저장');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'settings autosave text without leaving or pressing a save button',
    (tester) async {
      final storage = MemoryStorage();
      final store = await launch(tester, storage: storage);
      await tester.tap(find.byKey(const ValueKey('open-settings')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('profile-address-2')),
        '서울 종로구 세종대로 175',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(find.text('환경설정'), findsOneWidget);
      expect(store.profiles.addresses[2], '서울 종로구 세종대로 175');
      final restored = await AppStore.load(storage);
      expect(restored.profiles.addresses[2], '서울 종로구 세종대로 175');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'hiding the keyboard clears focus and tapping outside also dismisses it',
    (tester) async {
      await launch(tester);
      addTearDown(tester.view.resetViewInsets);
      await tester.tap(find.byKey(const ValueKey('open-settings')));
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('profile-name-0'));
      await tester.showKeyboard(field);
      await tester.pump();
      final editable = tester.widget<EditableText>(
        find.descendant(of: field, matching: find.byType(EditableText)),
      );
      expect(editable.focusNode.hasFocus, isTrue);
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding();
      await tester.pumpAndSettle();
      expect(editable.focusNode.hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
      await tester.showKeyboard(field);
      await tester.pump();
      expect(editable.focusNode.hasFocus, isTrue);
      await tester.tap(find.text('표시 이름'));
      await tester.pumpAndSettle();
      expect(editable.focusNode.hasFocus, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('CAPTURE_UI')) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('app-preview')),
    );
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory('build/ui-previews').create(recursive: true);
    await File('build/ui-previews/$name.png')
        .writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

class _PreviewBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get disableShadows => !const bool.fromEnvironment('CAPTURE_UI');
}
