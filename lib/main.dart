import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/local_store.dart';
import 'ui/screens/home_screen.dart';
import 'ui/theme.dart';

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
      ? AppStore.load(PreferencesStorage())
      : Future.value(widget.store!);

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
            child: child,
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
                  const Text('저장된 정보를 불러오지 못했어요.'),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => setState(
                      () => _store = AppStore.load(PreferencesStorage()),
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
