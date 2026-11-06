import 'package:flutter/material.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flake Chicken',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF222222)),
        scaffoldBackgroundColor: Colors.white,
      ),
      home: const CounterPage(),
    );
  }
}

class CounterPage extends StatefulWidget {
  const CounterPage({super.key});

  @override
  State<CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<CounterPage> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SizedBox.square(
            dimension: 48,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                FilledButton(
                  onPressed: () => setState(() => _count++),
                  style: FilledButton.styleFrom(
                    fixedSize: const Size.square(28),
                    minimumSize: Size.zero,
                    padding: EdgeInsets.zero,
                    backgroundColor: const Color(0xFF222222),
                    foregroundColor: Colors.white,
                    shape: const CircleBorder(),
                  ),
                  child: const Icon(
                    Icons.add,
                    size: 16,
                    semanticLabel: '1 더하기',
                  ),
                ),
                Positioned(
                  top: 48,
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      '$_count',
                      style: const TextStyle(
                        color: Color(0xFF222222),
                        fontSize: 20,
                        height: 1,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
