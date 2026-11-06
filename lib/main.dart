import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/local_store.dart';
import 'ui/screens/home_screen.dart';
import 'ui/theme.dart';
import 'ui/widgets/keyboard_focus_dismissal.dart';
import 'ui/widgets/cancellation_confetti.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: AppColors.background,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const FlakeChickenApp());
}

class FlakeChickenApp extends StatefulWidget {
  const FlakeChickenApp({super.key, this.store});
  final AppStore? store;

  @override
  State<FlakeChickenApp> createState() => _FlakeChickenAppState();
}

class _FlakeChickenAppState extends State<FlakeChickenApp> {
  late Future<AppStore> _store = widget.store == null
      ? AppStore.connect(PreferencesStorage(key: 'flake_chicken.connected.v1'))
      : Future.value(widget.store!);

  @override
  void dispose() {
    if (widget.store == null) {
      _store.then((store) => store.dispose(), onError: (_) {});
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Flake Chicken',
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    locale: const Locale('ko', 'KR'),
    supportedLocales: const [Locale('ko', 'KR'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    builder: (context, child) => RepaintBoundary(
      key: const ValueKey('app-preview'),
      child: ColoredBox(
        color: const Color(0xFFEDF2F8),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: FutureBuilder<AppStore>(
              future: _store,
              builder: (context, snapshot) => CancellationConfetti(
                store: snapshot.connectionState == ConnectionState.done
                    ? snapshot.data
                    : null,
                child: KeyboardFocusDismissal(child: child!),
              ),
            ),
          ),
        ),
      ),
    ),
    home: FutureBuilder<AppStore>(
      future: _store,
      builder: (context, snapshot) {
        if (snapshot.hasData) return HomeScreen(store: snapshot.requireData);
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('서버에 연결하지 못했어요.'),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => setState(
                      () => _store = AppStore.connect(
                        PreferencesStorage(key: 'flake_chicken.connected.v1'),
                      ),
                    ),
                    child: const Text('다시 시도'),
                  ),
                ],
              ),
            ),
          );
        }
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      },
    ),
  );
}
