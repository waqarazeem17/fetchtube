import 'package:flutter/material.dart';

import 'downloads.dart';
import 'history.dart';
import 'home.dart';
import 'theme.dart';

void main() async {
  // The store opens an EventChannel, which needs the binding to exist first.
  WidgetsFlutterBinding.ensureInitialized();
  DownloadStore.instance; // subscribe to native events before any UI can start one.
  await History.instance.load();
  runApp(const FetchTubeApp());
}

class FetchTubeApp extends StatelessWidget {
  const FetchTubeApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'FetchTube',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const HomeShell(),
      );
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  bool _libraryAudio = false;

  void _openLibrary({required bool audio}) => setState(() {
        _libraryAudio = audio;
        _tab = 1;
      });

  @override
  Widget build(BuildContext context) => Scaffold(
        body: _tab == 0
            ? HomeScreen(
                onOpenLibrary: _openLibrary,
                onOpenDownloads: () => setState(() => _tab = 1),
              )
            // The key rebuilds the tab controller so quick access lands on the
            // right tab instead of whichever one was last open.
            : DownloadsScreen(
                key: ValueKey(_libraryAudio),
                initialAudio: _libraryAudio,
              ),
        bottomNavigationBar: ListenableBuilder(
          listenable: DownloadStore.instance,
          builder: (context, _) {
            final active = DownloadStore.instance.activeCount;
            return NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (i) => setState(() => _tab = i),
              destinations: [
                const NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home),
                    label: 'Home'),
                NavigationDestination(
                  icon: Badge(
                    isLabelVisible: active > 0,
                    label: Text('$active'),
                    backgroundColor: kVideoAccent,
                    textColor: Colors.black,
                    child: const Icon(Icons.download_outlined),
                  ),
                  selectedIcon: const Icon(Icons.download),
                  label: 'Library',
                ),
              ],
            );
          },
        ),
      );
}
