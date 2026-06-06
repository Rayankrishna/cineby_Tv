import 'package:cineby_tv/services/config.dart';
import 'package:cineby_tv/services/pages/login_page.dart';
import 'package:cineby_tv/services/pages/root_shell.dart';
import 'package:cineby_tv/stores/stores.dart';
import 'package:cineby_tv/utils/tv_scale.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await authStore.bootstrap();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
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
          child: child!,
        );
      },
      home: Observer(
        builder: (_) => authStore.isAuthenticated
            ? const RootShell()
            : LoginPage(authStore: authStore),
      ),
    );
  }
}
