import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/providers.dart';
import 'audio/audio_service.dart';
import 'game/autoplay_bot.dart' show kPromoAutoplay;
import 'l10n/app_localizations.dart';
import 'services/achievements.dart';
import 'services/ads.dart';
import 'services/content.dart';
import 'services/error_log.dart';
import 'services/leaderboard.dart';
import 'services/records.dart';
import 'services/review.dart';
import 'services/settings.dart';
import 'ui/title/title_screen.dart';
import 'ui/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ErrorLog.install();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(await buildRoot(rootBundle));
}

/// 起動時の読み込み (保存データ・ステージの JSON) をして、最初に出すウィジェットを作る。
/// 読み込めなければ、起動画面のまま止まらないよう [StartupErrorApp] を返す。
Future<Widget> buildRoot(AssetBundle bundle) async {
  final SharedPreferences prefs;
  final GameContent content;
  try {
    prefs = await SharedPreferences.getInstance();
    content = await GameContent.load(bundle);
  } on Object catch (e, st) {
    ErrorLog.record(e, st, context: 'startup');
    return StartupErrorApp(error: e);
  }
  final audio = createAudioService();
  return ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      contentProvider.overrideWithValue(content),
      audioProvider.overrideWithValue(audio),
      adsProvider.overrideWithValue(createAdsService(prefs)),
      reviewProvider.overrideWithValue(createReviewService(prefs)),
    ],
    child: ParryBreakApp(audioInit: audio.init()),
  );
}

/// 起動時の読み込みに失敗したときの画面。言語は端末の設定に従う (保存した設定は読めないことがあるため)。
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'PARRY BREAK',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(
      builder: (context) {
        final l = AppLocalizations.of(context);
        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l.startupErrorTitle,
                      style: pixelFont(22),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l.startupErrorBody,
                      style: const TextStyle(fontSize: 16, height: 1.5),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
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

class _ParryBreakAppState extends ConsumerState<ParryBreakApp>
    with WidgetsBindingObserver {
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
    unawaited(
      widget.audioInit?.then((_) {
        final s = ref.read(settingsProvider);
        ref.read(audioProvider).setVolumes(bgm: s.bgmVolume, sfx: s.sfxVolume);
      }),
    );
    unawaited(
      ref.read(leaderboardProvider).signIn().then((_) {
        // サインインのあとで、送れていなかった実績を送り、進行の実績を見直す
        return ref
            .read(achievementsProvider)
            .sync(
              ref.read(recordsProvider),
              ref.read(contentProvider).campaign,
            );
      }),
    );
    // 同意の画面を出すことがあるので、最初の画面が出てから始める
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(ref.read(adsProvider).init()),
    );
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
      builder: debug && !kPromoAutoplay
          ? (context, child) => Banner(
              message: 'DEBUG',
              location: BannerLocation.bottomStart,
              child: child!,
            )
          : null,
    );
  }
}
