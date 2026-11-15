import '../core/core.dart';
import '../l10n/app_localizations.dart';
import '../services/quests.dart';

/// 今日のお題の説明文 (パネルに出す)。
String questText(AppLocalizations l, Quest q) {
  final n = q.target;
  return switch (q.kind) {
    QuestKind.plays => l.questPlays('$n'),
    QuestKind.dailyPlay => l.questDaily,
    QuestKind.perfect => l.questPerfect('$n'),
    QuestKind.just => l.questJust('$n'),
    QuestKind.fever => l.questFever('$n'),
    QuestKind.endlessRound => l.questRound('$n'),
    QuestKind.stageClear => l.questStage('$n'),
    QuestKind.returnKills => l.questReturn('$n'),
    QuestKind.endlessScore => l.questScore(formatScore(n)),
  };
}

/// 進みの数 (「7/20」。スコアは桁区切りを付ける)。
String questCount(Quest q) => q.kind == QuestKind.endlessScore
    ? '${formatScore(q.progress)}/${formatScore(q.target)}'
    : '${q.progress}/${q.target}';

/// 結果画面の 1 行に入れる短い名前 (「PERFECT ×20」)。英語のまま (LV / XP と同じ)。
String questShort(Quest q) {
  final n = q.target;
  return switch (q.kind) {
    QuestKind.plays => 'PLAY ×$n',
    QuestKind.dailyPlay => 'DAILY',
    QuestKind.perfect => 'PERFECT ×$n',
    QuestKind.just => 'JUST ×$n',
    QuestKind.fever => 'FEVER ×$n',
    QuestKind.endlessRound => 'ROUND $n',
    QuestKind.stageClear => 'STAGE ×$n',
    QuestKind.returnKills => 'RETURN ×$n',
    QuestKind.endlessScore => 'SCORE ${formatScore(n)}',
  };
}

/// 結果画面の「QUEST CLEAR: PERFECT ×20 +100 XP」の行。複数なら最初の 1 つのあとに「ほか N」を付ける。
/// 3 つ全部が終わった回は、追加の分も合わせた XP を 1 つにして出す。
String questClearLine(AppLocalizations l, QuestResult r) {
  if (r.allClear) return 'ALL QUESTS CLEAR! +${r.xp} XP';
  final first = r.cleared.first;
  final text = 'QUEST CLEAR: ${questShort(first)} +${first.xp} XP';
  return r.cleared.length == 1
      ? text
      : '$text ${l.questMore('${r.cleared.length - 1}')}';
}
