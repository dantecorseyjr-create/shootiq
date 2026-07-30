import 'package:shootiq/models/shot_coach_context.dart';

/// Topics for natural-language questions about a single analysis.
enum ShotCoachTopic {
  lostPoints,
  biggestMistake,
  drills,
  compare,
  proModel,
  practiceToday,
  formMechanics,
  release,
  balance,
  followThrough,
  load,
  howToImprove,
  offTopic,
  general,
}

/// Context-aware shot coach. Remembers the current analysis across turns.
///
/// Uses structured analysis data (score, categories, timeline, profile,
/// history) to produce personalized replies until a remote LLM is wired up.
class ShotCoachService {
  ShotCoachService._();

  static const offTopicRedirect =
      "I'm your ShootIQ Shooting Coach. I can help with shooting form, "
      'mechanics, drills, and player development.';

  static const _offTopicKeys = [
    'stock',
    'crypto',
    'bitcoin',
    'invest',
    'weather',
    'recipe',
    'cook',
    'politics',
    'election',
    'movie',
    'netflix',
    'dating',
    'girlfriend',
    'boyfriend',
  ];

  static const _basketballKeys = [
    'shoot',
    'shot',
    'form',
    'release',
    'elbow',
    'balance',
    'arc',
    'drill',
    'workout',
    'practice',
    'score',
    'point',
    'mistake',
    'curry',
    'steph',
    'nba',
    'follow',
    'wrist',
    'knee',
    'load',
    'improve',
    'fix',
    'compare',
    'analysis',
  ];

  static String reply({
    required String question,
    required ShotCoachContext context,
    List<String> priorUserQuestions = const [],
  }) {
    final raw = question.trim();
    if (raw.isEmpty) {
      return 'Ask me anything about this shot — mechanics, drills, or how it '
          'compares to your recent sessions.';
    }

    final q = raw.toLowerCase();
    if (_isOffTopic(q)) return offTopicRedirect;

    final topic = classify(q, priorUserQuestions: priorUserQuestions);
    final priorTopic = _lastConcreteTopic(priorUserQuestions);
    final followUpHint = _followUpHint(q, priorUserQuestions);

    switch (topic) {
      case ShotCoachTopic.lostPoints:
        return _whyLostPoints(context, followUpHint);
      case ShotCoachTopic.biggestMistake:
        return _biggestMistake(context, followUpHint);
      case ShotCoachTopic.drills:
        return _drills(context, followUpHint ?? _topicLabel(priorTopic));
      case ShotCoachTopic.compare:
        return _compareLast(context, followUpHint);
      case ShotCoachTopic.proModel:
        return _stephCurry(context, followUpHint);
      case ShotCoachTopic.practiceToday:
        return _practiceToday(context, followUpHint);
      case ShotCoachTopic.formMechanics:
        return _categoryDeepDive(context, 'elbow', followUpHint);
      case ShotCoachTopic.release:
        return _categoryDeepDive(context, 'release', followUpHint);
      case ShotCoachTopic.balance:
        return _categoryDeepDive(context, 'balance', followUpHint);
      case ShotCoachTopic.followThrough:
        return _categoryDeepDive(context, 'follow', followUpHint);
      case ShotCoachTopic.load:
        return _categoryDeepDive(context, 'load', followUpHint);
      case ShotCoachTopic.howToImprove:
        return _general(context, raw, followUpHint, forceImprove: true);
      case ShotCoachTopic.offTopic:
        return offTopicRedirect;
      case ShotCoachTopic.general:
        return _general(context, raw, followUpHint);
    }
  }

  static ShotCoachTopic classify(
    String q, {
    List<String> priorUserQuestions = const [],
  }) {
    final lower = q.toLowerCase();

    if (_isOffTopic(lower)) return ShotCoachTopic.offTopic;

    if (_isVagueFollowUp(lower)) {
      final prior = _lastConcreteTopic(priorUserQuestions);
      if (prior != null) return prior;
    }

    if (_matches(lower, [
      'lose points',
      'lost points',
      'why did i',
      'why was my score',
      'explain my score',
      'deduct',
    ])) {
      return ShotCoachTopic.lostPoints;
    }

    if (_matches(lower, [
      'biggest mistake',
      'main mistake',
      'worst',
      'most important',
      'primary issue',
    ])) {
      return ShotCoachTopic.biggestMistake;
    }

    if (_matches(lower, [
      'compare',
      'last shot',
      'previous',
      'vs my',
      'versus',
      'history',
    ])) {
      return ShotCoachTopic.compare;
    }

    if (_matches(lower, [
      'steph',
      'curry',
      'nba',
      'pro',
      'like a pro',
    ])) {
      return ShotCoachTopic.proModel;
    }

    if (_matches(lower, [
      'practice today',
      'what should i practice',
      'focus today',
      "today's",
      'train today',
    ])) {
      return ShotCoachTopic.practiceToday;
    }

    if (_matches(lower, [
      'drill',
      'drills',
      'exercise',
      'workout',
      'practice plan',
      'what drill',
      'helps that',
    ])) {
      if (_isVagueFollowUp(lower)) {
        final prior = _lastConcreteTopic(priorUserQuestions);
        if (prior != null && prior != ShotCoachTopic.drills) return prior;
      }
      return ShotCoachTopic.drills;
    }

    if (_matches(lower, [
      'elbow',
      'alignment',
      'shot pocket',
      'set point',
      'inconsistent',
      'mechanics',
      'form',
    ])) {
      return ShotCoachTopic.formMechanics;
    }

    if (_matches(lower, ['release', 'timing', 'let go', 'too slow', 'faster'])) {
      return ShotCoachTopic.release;
    }

    if (_matches(lower, [
      'balance',
      'stance',
      'feet',
      'fall forward',
      'fading',
      'fade',
    ])) {
      return ShotCoachTopic.balance;
    }

    if (_matches(lower, ['follow', 'finish', 'wrist', 'follow through'])) {
      return ShotCoachTopic.followThrough;
    }

    if (_matches(lower, ['knee', 'load', 'legs', 'arc', 'short'])) {
      return ShotCoachTopic.load;
    }

    if (_matches(lower, [
      'improve',
      'how do i',
      'fix my',
      'get better',
      'what should i',
    ])) {
      return ShotCoachTopic.howToImprove;
    }

    return ShotCoachTopic.general;
  }

  static bool _isOffTopic(String q) {
    if (_offTopicKeys.any(q.contains) && !_basketballKeys.any(q.contains)) {
      return true;
    }
    return false;
  }

  static bool _matches(String q, List<String> keys) =>
      keys.any((k) => q.contains(k));

  static bool _isVagueFollowUp(String lower) {
    if (_matches(lower, [
      'what drill',
      'which drill',
      'drill for that',
      'helps that',
      'help with that',
      'more detail',
      'explain more',
      'tell me more',
      'fix that',
      'how do i fix that',
      'why does that',
      'same thing',
    ])) {
      return true;
    }
    final words = lower
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    return words.length <= 3 &&
        _matches(lower, [
          'more',
          'why',
          'how',
          'again',
          'drill',
          'drills',
          'that',
          'this',
          'yes',
          'yeah',
          'ok',
          'okay',
        ]);
  }

  static ShotCoachTopic? _lastConcreteTopic(List<String> prior) {
    for (final q in prior.reversed) {
      final t = classify(q.toLowerCase(), priorUserQuestions: const []);
      if (t == ShotCoachTopic.general || t == ShotCoachTopic.offTopic) {
        continue;
      }
      if (_isVagueFollowUp(q.toLowerCase())) continue;
      return t;
    }
    return null;
  }

  static String? _topicLabel(ShotCoachTopic? topic) {
    if (topic == null) return null;
    switch (topic) {
      case ShotCoachTopic.release:
        return 'release';
      case ShotCoachTopic.formMechanics:
        return 'elbow / form';
      case ShotCoachTopic.balance:
        return 'balance';
      case ShotCoachTopic.followThrough:
        return 'follow-through';
      case ShotCoachTopic.load:
        return 'leg load / arc';
      case ShotCoachTopic.lostPoints:
        return 'point losses';
      case ShotCoachTopic.biggestMistake:
        return 'biggest mistake';
      default:
        return null;
    }
  }

  static String? _followUpHint(String q, List<String> prior) {
    if (prior.isEmpty) return null;
    if (_isVagueFollowUp(q) ||
        _matches(q, ['more', 'detail', 'explain', 'why', 'how', 'again'])) {
      return prior.last;
    }
    return null;
  }

  static String _intro(ShotCoachContext ctx) {
    final profile = ctx.profileSummary;
    final scoreLine = 'This shot scored **${ctx.overallScore}/100**.';
    if (profile == null || profile.isEmpty) return scoreLine;
    return 'For $profile — $scoreLine';
  }

  static String _categoryLines(ShotCoachContext ctx) {
    if (ctx.categoryScores.isEmpty) return '';
    final lines = ctx.categoryScores.entries
        .map((e) => '• ${e.key}: ${e.value}')
        .join('\n');
    return '\n\nCategory scores:\n$lines';
  }

  static String _coachCard({
    required ShotCoachContext ctx,
    required String title,
    required String problem,
    required String why,
    required String fix,
    required String drill,
    String? followUp,
  }) {
    final buf = StringBuffer()
      ..writeln(_intro(ctx))
      ..writeln()
      ..writeln('### $title')
      ..writeln()
      ..writeln('**Problem:** $problem')
      ..writeln()
      ..writeln('**Why:** $why')
      ..writeln()
      ..writeln('**Fix:** $fix')
      ..writeln()
      ..writeln('**Drill:** $drill');

    if (followUp != null) {
      buf
        ..writeln()
        ..writeln(
          '_Still coaching from your last question (“$followUp”)._',
        );
    }
    return buf.toString().trim();
  }

  static String _whyLostPoints(ShotCoachContext ctx, String? followUp) {
    final buf = StringBuffer()
      ..writeln(_intro(ctx))
      ..writeln()
      ..writeln('### Why you lost points');

    if (ctx.pointLosses.isEmpty && ctx.priorities.isEmpty) {
      buf.writeln(
        'Mechanics look solid overall. Small timing and consistency '
        'tweaks are the main remaining upside.',
      );
    } else {
      final losses = ctx.pointLosses.take(3).toList();
      if (losses.isNotEmpty) {
        for (final loss in losses) {
          buf
            ..writeln()
            ..writeln('**${loss.category} −${loss.pointsLost}**')
            ..writeln('Reason: ${loss.reason}');
        }
      } else {
        for (final p in ctx.priorities.take(3)) {
          buf
            ..writeln()
            ..writeln('**${p.category}** (score ${p.score})')
            ..writeln(p.observation)
            ..writeln('Fix: ${p.fix}');
        }
      }
    }

    if (ctx.priorities.isNotEmpty) {
      final top = ctx.priorities.first;
      buf
        ..writeln()
        ..writeln('**Problem:** Biggest limiter is **${top.category}**.')
        ..writeln()
        ..writeln('**Fix:** ${top.fix}');
    }

    buf.write(_categoryLines(ctx));
    if (followUp != null) {
      buf
        ..writeln()
        ..writeln(
          'Building on your last question (“$followUp”), focus on one cue '
          'per set so the adjustment sticks.',
        );
    }
    return buf.toString().trim();
  }

  static String _biggestMistake(ShotCoachContext ctx, String? followUp) {
    final top = ctx.priorities.isNotEmpty ? ctx.priorities.first : null;
    final weak = ctx.weakestCategory;
    final topIssue = top?.observation ??
        (ctx.issues.isNotEmpty
            ? ctx.issues.first
            : ctx.improvementSummary ??
                (weak != null
                    ? '${weak.key} needs the most work'
                    : 'No major mechanical fault stood out'));

    final correction = top?.fix ??
        (ctx.recommendations.isNotEmpty
            ? ctx.recommendations.first
            : 'Film 10 free throws focusing on a single cue.');

    final category = top?.category ?? weak?.key ?? 'overall form';

    return _coachCard(
      ctx: ctx,
      title: 'Biggest mistake',
      problem: topIssue,
      why: 'That maps to **$category**'
          '${top != null ? ' at ${top.score}' : weak != null ? ' at ${weak.value}' : ''}'
          ' — own that category and the rest of the form usually cleans up with it.',
      fix: correction,
      drill: '12–15 focused minutes on $category. Stop the set when form breaks.',
      followUp: followUp,
    );
  }

  static String _drills(ShotCoachContext ctx, String? followUp) {
    final weak = ctx.weakestCategory?.key.toLowerCase() ?? '';
    final focusLabel = followUp ?? ctx.weakestCategory?.key ?? 'overall form';
    final drills = <String>[];

    if (weak.contains('elbow') ||
        weak.contains('set') ||
        (followUp?.contains('elbow') ?? false) ||
        (followUp?.contains('form') ?? false)) {
      drills.addAll([
        'Form shooting at 5–8 feet — elbow under the ball, 3 makes before step back',
        'Wall touch drill — raise to set point and touch the wall with the shooting elbow path',
        'One-hand form shots (no guide hand) for 2 minutes',
      ]);
    } else if (weak.contains('balance') ||
        weak.contains('feet') ||
        weak.contains('stance') ||
        (followUp?.contains('balance') ?? false)) {
      drills.addAll([
        'Stance holds — freeze your base for 2 seconds before every shot',
        '1-2 step into shot from a closed stance, land balanced',
        'Chair drill — sit-to-stand into a catch-and-shoot without hopping',
      ]);
    } else if (weak.contains('follow') ||
        weak.contains('wrist') ||
        (followUp?.contains('follow') ?? false)) {
      drills.addAll([
        'Hold the goose-neck finish until the ball hits the rim',
        'Wrist flips against a wall — soft fingertips, high finish',
        'One-motion shooting focusing on a quiet guide hand',
      ]);
    } else if (weak.contains('release') ||
        weak.contains('timing') ||
        (followUp?.contains('release') ?? false)) {
      drills.addAll([
        'Jump-and-hold — jump, pause at peak, then release (then remove the pause)',
        'Rhythm 1-2-shoot with a metronome or count',
        'Close-range swishes — release at the top of the jump only',
      ]);
    } else if (weak.contains('knee') ||
        weak.contains('load') ||
        weak.contains('arc') ||
        (followUp?.contains('arc') ?? false) ||
        (followUp?.contains('load') ?? false)) {
      drills.addAll([
        'Dip-and-rise form shots — feel the legs load before the arms move',
        'Mikan variation with a deep knee bend each rep',
        'Power dribble into a stop-and-pop, emphasizing leg drive',
      ]);
    } else {
      drills.addAll([
        '25 make form shooting — perfect mechanics only',
        'Spot shooting: 5 spots × 8 makes',
        'Free-throw routine with the same breath and stance every time',
      ]);
    }

    final buf = StringBuffer()
      ..writeln(_intro(ctx))
      ..writeln()
      ..writeln('### Drills for $focusLabel')
      ..writeln()
      ..writeln(
        '**Problem:** ${ctx.weakestCategory != null ? '${ctx.weakestCategory!.key} (${ctx.weakestCategory!.value}) needs the work' : 'Consistency under this analysis'}.',
      )
      ..writeln()
      ..writeln('**Drill plan:**');
    for (var i = 0; i < drills.length; i++) {
      buf.writeln('${i + 1}. ${drills[i]}');
    }
    buf
      ..writeln()
      ..writeln(
        'Do 12–15 focused minutes. Quality over volume — stop a set '
        'when form breaks down.',
      );

    if (ctx.recommendations.isNotEmpty) {
      buf
        ..writeln()
        ..writeln('**Fix / cue:** “${ctx.recommendations.first}”');
    }
    if (followUp != null &&
        !focusLabel.contains(followUp) &&
        followUp.length > 3) {
      buf
        ..writeln()
        ..writeln('_Tied to your last question about “$followUp”._');
    }
    return buf.toString().trim();
  }

  static String _compareLast(ShotCoachContext ctx, String? followUp) {
    final buf = StringBuffer()..writeln(_intro(ctx));

    if (ctx.previousShots.isEmpty) {
      buf
        ..writeln()
        ..writeln(
          'I do not have an earlier shot in your history yet. '
          'Analyze one more session and I can compare elbow, balance, '
          'follow-through, and overall score side by side.',
        );
      return buf.toString().trim();
    }

    final last = ctx.previousShots.first;
    final delta = ctx.overallScore - last.score;
    final trend = delta > 0
        ? 'up $delta points from your previous shot (${last.score})'
        : delta < 0
            ? 'down ${delta.abs()} points from your previous shot (${last.score})'
            : 'even with your previous shot (${last.score})';

    buf
      ..writeln()
      ..writeln('### Compared to your last shot')
      ..writeln()
      ..writeln('**Problem:** You want to know what changed.')
      ..writeln()
      ..writeln('**Why it matters:** Trend tells us whether the cue is sticking.')
      ..writeln()
      ..writeln('**Result:** You are $trend.')
      ..writeln()
      ..writeln('Last shot snapshot:')
      ..writeln('• Overall: ${last.score}')
      ..writeln('• Elbow: ${last.elbow}')
      ..writeln('• Balance: ${last.balance}')
      ..writeln('• Follow-through: ${last.followThrough}');

    if (last.topIssue != null && last.topIssue!.trim().isNotEmpty) {
      buf.writeln('• Prior focus: ${last.topIssue}');
    }

    final weak = ctx.weakestCategory;
    if (weak != null) {
      buf
        ..writeln()
        ..writeln(
          '**Fix next:** ${weak.key} (${weak.value}). '
          'Double down on the same drill block for consistency.',
        );
    }

    if (ctx.previousShots.length > 1) {
      final avg = (ctx.previousShots.map((s) => s.score).reduce((a, b) => a + b) /
              ctx.previousShots.length)
          .round();
      buf
        ..writeln()
        ..writeln(
          'Recent average across ${ctx.previousShots.length} shots: $avg. '
          'Your current ${ctx.overallScore} is '
          '${ctx.overallScore >= avg ? 'at or above' : 'below'} that trend.',
        );
    }

    return buf.toString().trim();
  }

  static String _stephCurry(ShotCoachContext ctx, String? followUp) {
    final weak = ctx.weakestCategory;
    final strong = ctx.strongestCategory;
    final gap = weak != null
        ? '${weak.key} (${weak.value})'
        : 'repeatability under pace';
    final keep = strong != null && strong.value >= 80
        ? '${strong.key} (${strong.value})'
        : 'your cleanest category';

    return _coachCard(
      ctx: ctx,
      title: 'Pro model (Steph)',
      problem: 'You want a more Curry-like, repeatable jumper.',
      why: 'Steph’s form is a quiet base, high set point, quick one-motion release, '
          'and a frozen high finish. Gap vs that model right now: **$gap**.',
      fix: 'Keep **$keep**. Steal: same foot angle every catch, ball to set point '
          'in one path, hold the finish until rim or net.',
      drill: '10 catch-and-shoot with a frozen finish, then 10 one-motion form makes. '
          'Copy repeatability first — not his range.',
      followUp: followUp,
    );
  }

  static String _practiceToday(ShotCoachContext ctx, String? followUp) {
    final weak = ctx.weakestCategory;
    final focus = weak?.key ?? 'overall form consistency';
    final cue = ctx.recommendations.isNotEmpty
        ? ctx.recommendations.first
        : 'Smooth path to a high finish';

    return _coachCard(
      ctx: ctx,
      title: "Today's practice plan",
      problem: 'You need a clear 20-minute session from this analysis.',
      why: '**$focus** is the limiter on this shot — that should own the middle block.',
      fix: 'Cue on a loop: “$cue”',
      drill: '1) Warm-up 4 min form inside the lane  '
          '2) Focus block 10 min on $focus  '
          '3) Transfer 4 min catch-and-shoot from 3 spots  '
          '4) Free throws 2 min with full routine. '
          'Film the last 5 makes.',
      followUp: followUp,
    );
  }

  static String _categoryDeepDive(
    ShotCoachContext ctx,
    String key,
    String? followUp,
  ) {
    final match = ctx.categoryScores.entries.where(
      (e) =>
          e.key.toLowerCase().contains(key) ||
          (key == 'load' && e.key.toLowerCase().contains('knee')) ||
          (key == 'load' && e.key.toLowerCase().contains('arc')),
    );

    final score = match.isEmpty ? null : match.first;
    final relatedIssues = ctx.issues
        .where((i) => i.toLowerCase().contains(key))
        .toList();
    final relatedFixes = ctx.recommendations
        .where((r) => r.toLowerCase().contains(key))
        .toList();

    final label = score?.key ?? _prettyKey(key);
    final problem = relatedIssues.isNotEmpty
        ? relatedIssues.first
        : (score != null
            ? '$label scored ${score.value}/100 on this shot.'
            : 'This area needs attention on this shot.');
    final fix = relatedFixes.isNotEmpty
        ? relatedFixes.first
        : (ctx.recommendations.isNotEmpty
            ? ctx.recommendations.first
            : 'Film 10 reps with one short cue for $label.');
    final why = score != null
        ? 'At ${score.value}/100, $label is '
            '${score.value < 78 ? 'a clear limiter' : 'close — consistency is the upside'}.'
        : 'Your analysis notes point back to this phase of the shot.';

    final drill = _drillForKey(key);

    final buf = StringBuffer(
      _coachCard(
        ctx: ctx,
        title: label,
        problem: problem,
        why: why,
        fix: fix,
        drill: drill,
        followUp: followUp,
      ),
    );
    _appendTimeline(buf, ctx);
    return buf.toString().trim();
  }

  static String _prettyKey(String key) {
    switch (key) {
      case 'elbow':
        return 'Elbow alignment';
      case 'release':
        return 'Release timing';
      case 'balance':
        return 'Balance';
      case 'follow':
        return 'Follow-through';
      case 'load':
        return 'Leg load / arc';
      default:
        return key;
    }
  }

  static String _drillForKey(String key) {
    switch (key) {
      case 'elbow':
        return '50 form shots close — elbow under the ball every rep.';
      case 'release':
        return 'Jump-and-hold × 15, then 20 rhythm makes releasing at the top.';
      case 'balance':
        return 'Stance holds 2 seconds before every shot, then 1-2 step catch-and-shoot × 20.';
      case 'follow':
        return '25 one-hand form makes with a frozen goose-neck finish.';
      case 'load':
        return 'Dip-and-rise form shots × 30 — legs load before the arms move.';
      default:
        return '25 perfect-form makes with one cue only.';
    }
  }

  static String _general(
    ShotCoachContext ctx,
    String question,
    String? followUp, {
    bool forceImprove = false,
  }) {
    final weak = ctx.weakestCategory;
    final strong = ctx.strongestCategory;
    final lower = question.toLowerCase();
    final wantsImprove = forceImprove ||
        _matches(lower, [
          'improve',
          'how do i',
          'fix my',
          'get better',
          'what should i',
        ]);

    final buf = StringBuffer()
      ..writeln(_intro(ctx))
      ..writeln();

    if (wantsImprove && ctx.priorities.isNotEmpty) {
      final top = ctx.priorities.first;
      buf
        ..writeln('### How to improve this shot')
        ..writeln()
        ..writeln('**Problem:** ${top.observation}')
        ..writeln()
        ..writeln(
          '**Why:** **${top.category}** at ${top.score} is your biggest limiter'
          '${strong != null ? ' (keep ${strong.key} at ${strong.value})' : ''}.',
        )
        ..writeln()
        ..writeln('**Fix:** ${top.fix}')
        ..writeln()
        ..writeln(
          '**Drill:** 12 minutes on ${top.category}, then 8 catch-and-shoot '
          'transfers with the same cue.',
        );

      if (ctx.priorities.length > 1) {
        buf
          ..writeln()
          ..writeln('Also on deck:');
        for (final p in ctx.priorities.skip(1).take(2)) {
          buf.writeln('- **${p.category}**: ${p.fix}');
        }
      }
    } else {
      buf
        ..writeln('You asked: “$question”')
        ..writeln()
        ..writeln('**Problem:** I want to coach from this exact analysis.')
        ..writeln()
        ..writeln('Based on this shot:');

      if (strong != null) {
        buf.writeln('• Keep: ${strong.key} (${strong.value})');
      }
      if (weak != null) {
        buf.writeln('• Fix next: ${weak.key} (${weak.value})');
      }
      if (ctx.improvementSummary != null) {
        buf.writeln('• Coach note: ${ctx.improvementSummary}');
      } else if (ctx.recommendations.isNotEmpty) {
        buf.writeln('• Cue: ${ctx.recommendations.first}');
      }

      buf
        ..writeln()
        ..writeln(
          '**Fix:** Ask about elbow, balance, release, follow-through, '
          'or type anything natural — “Why do I fall forward?” works.',
        )
        ..writeln()
        ..writeln(
          '**Drill:** Tap a suggested question, or ask “What drill helps that?” '
          'after we pick a focus.',
        );
    }

    if (followUp != null) {
      buf
        ..writeln()
        ..writeln(
          'Continuing from “$followUp” — stay on one mechanical cue for '
          'the next practice block.',
        );
    }
    return buf.toString().trim();
  }

  static void _appendTimeline(StringBuffer buf, ShotCoachContext ctx) {
    if (ctx.timeline.isEmpty) return;
    final weakPhases = ctx.timeline
        .where((t) => t.status.toUpperCase() != 'PASS')
        .take(3)
        .toList();
    if (weakPhases.isEmpty) return;
    buf
      ..writeln()
      ..writeln('Phases to rewatch:');
    for (final phase in weakPhases) {
      final stamp = phase.timestamp.isNotEmpty ? ' @ ${phase.timestamp}' : '';
      buf.writeln('• ${phase.phase}$stamp (${phase.status})');
    }
  }
}
