import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/providers.dart';
import 'audio/audio_service.dart';
import 'l10n/app_localizations.dart';
import 'services/ads.dart';
import 'services/content.dart';
import 'services/leaderboard.dart';
import 'services/settings.dart';
import 'ui/title/title_screen.dart';
import 'ui/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  final prefs = await SharedPreferences.getInstance();
  final content = await GameContent.load(rootBundle);
  final audio = createAudioService();
  runApp(ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      contentProvider.overrideWithValue(content),
      audioProvider.overrideWithValue(audio),
      adsProvider.overrideWithValue(createAdsService(prefs)),
    ],
    child: ParryBreakApp(audioInit: audio.init()),
  ));
}

class ParryBreakApp extends ConsumerStatefulWidget {
  const ParryBreakApp({super.key, this.audioInit, this.home});

  /// 音の準備 (効果音・BGM の生成) は起動を待たせずに裏で進める。
  final Future<void>? audioInit;

  /// 最初の画面 (テスト用。省くとタイトル)。
  final Widget? home;

  @override
  ConsumerState<ParryBreakApp> createState() => _ParryBreakAppState();
}

class _ParryBreakAppState extends ConsumerState<ParryBreakApp> with WidgetsBindingObserver {
  late final AudioService _audio = ref.read(audioProvider);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _audio.setAppActive(state == AppLifecycleState.resumed);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(widget.audioInit?.then((_) {
      final s = ref.read(settingsProvider);
      ref.read(audioProvider).setVolumes(bgm: s.bgmVolume, sfx: s.sfxVolume);
    }));
    unawaited(ref.read(leaderboardProvider).signIn());
    // 同意の画面を出すことがあるので、最初の画面が出てから始める
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(ref.read(adsProvider).init()));
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(settingsProvider.select((s) => s.language));
    final debug = ref.watch(debugModeProvider);
    return MaterialApp(
      title: 'PARRY BREAK',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      locale: lang == null ? null : Locale(lang),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: widget.home ?? const TitleScreen(),
      // デバッグモード中はどの画面でも分かるように帯を出す
      builder: debug ? (context, child) => Banner(message: 'DEBUG', location: BannerLocation.bottomStart, child: child!) : null,
    );
  }
}
