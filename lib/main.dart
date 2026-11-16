import 'package:cineby_tv/services/config.dart';
import 'package:cineby_tv/services/pages/login_page.dart';
import 'package:cineby_tv/services/pages/root_shell.dart';
import 'package:cineby_tv/stores/stores.dart';
import 'package:cineby_tv/utils/tv_scale.dart';
import 'package:cineby_tv/widgets/tv_focus.dart';
import 'package:cineby_tv/widgets/tv_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

/// One policy instance for the whole app: it carries D-pad history, so it
/// must not be recreated on rebuild.
final TvTraversalPolicy _traversalPolicy = TvTraversalPolicy();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  TvInput.ensureInstalled();
  await authStore.bootstrap();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    const transitions = TvPageTransitionsBuilder();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ReelixTv',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kDeepBlack,
        colorScheme: ColorScheme.fromSeed(
          seedColor: kNetflixRed,
          brightness: Brightness.dark,
        ),
        // A remote has no touch feedback to give.
        splashFactory: NoSplash.splashFactory,
        pageTransitionsTheme: PageTransitionsTheme(
          builders: {
            for (final platform in TargetPlatform.values) platform: transitions,
          },
        ),
        textTheme: const TextTheme().apply(
          bodyColor: kTextWhite,
          displayColor: kTextWhite,
        ),
      ),
      builder: (context, child) {
        final media = MediaQuery.of(context);
        final scale = (media.size.width / kTvDesignWidth).clamp(0.75, 2.5);
        return MediaQuery(
          data: media.copyWith(textScaler: TextScaler.linear(scale)),
          // Smooth, animated D-pad scrolling everywhere (see TvTraversalPolicy).
          child: FocusTraversalGroup(
            policy: _traversalPolicy,
            child: TvKeyPacer(child: child!),
          ),
        );
      },
      home: Observer(
        builder:
            (_) =>
                authStore.isAuthenticated
                    ? const RootShell()
                    : LoginPage(authStore: authStore),
      ),
    );
  }
}
