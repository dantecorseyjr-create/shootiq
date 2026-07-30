import 'package:shootiq/services/ai_coach_personalization.dart';
import 'package:shootiq/services/training_drills_service.dart';

/// Shooting topic used to classify free-typed and suggested questions.
enum CoachTopic {
  formMechanics,
  release,
  arc,
  balance,
  range,
  footwork,
  mental,
  training,
  howToImprove,
  progress,
  freeThrows,
  threes,
  midrange,
  shotTypes,
  recovery,
  levels,
  followUpMenu,
  offTopic,
  general,
}

/// General AI Shooting Coach — not limited to a single uploaded video.
class AiCoachService {
  AiCoachService._();

  static const offTopicRedirect =
      "I'm your ShootIQ Shooting Coach. I can help with shooting form, "
      'mechanics, drills, and player development.';

  static const _basketballKeys = [
    'shoot',
    'shot',
    'basket',
    'hoop',
    'ball',
    'form',
    'release',
    'elbow',
    'wrist',
    'follow',
    'balance',
    'stance',
    'foot',
    'feet',
    'arc',
    'range',
    'three',
    '3pt',
    'mid-range',
    'midrange',
    'free throw',
    'ft ',
    'floater',
    'fadeaway',
    'step back',
    'step-back',
    'dribble',
    'catch',
    'rim',
    'finish',
    'layup',
    'drill',
    'workout',
    'train',
    'practice',
    'pregame',
    'warm',
    'recover',
    'confidence',
    'pressure',
    'nervous',
    'nba',
    'wnba',
    'ncaa',
    'college',
    'youth',
    'curry',
    'steph',
    'kobe',
    'ray allen',
    'kd',
    'durant',
    'set point',
    'shot pocket',
    'guide hand',
    'thumb',
    'flick',
    'jump shot',
    'jumper',
    'mechanics',
    'consistency',
    'inconsistent',
    'score',
    'analysis',
    'analyze',
    'coach',
    'player',
    'offense',
    'guard',
    'forward',
    'center',
    'routine',
    'reps',
    'make',
    'swish',
    'power',
    'deeper',
    'short',
    'fading',
    'fall forward',
  ];

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
    'homework math',
    'calculus',
    'code this',
    'write python',
    'dating',
    'girlfriend',
    'boyfriend',
  ];

  static bool isOnTopic(String question) {
    final q = question.toLowerCase();
    if (_offTopicKeys.any(q.contains) && !_basketballKeys.any(q.contains)) {
      return false;
    }
    // Short vague prompts / follow-ups are treated as coaching intents.
    if (q.trim().split(RegExp(r'\s+')).length <= 6) return true;
    return _basketballKeys.any(q.contains);
  }

  /// Classifies a natural-language shooting question into a coaching topic.
  static CoachTopic classify(
    String question, {
    List<String> priorUserQuestions = const [],
  }) {
    final q = question.trim();
    if (q.isEmpty) return CoachTopic.general;

    if (!isOnTopic(q)) return CoachTopic.offTopic;

    final lower = q.toLowerCase();

    if (_matches(lower, ['follow-up', 'follow up', 'ask follow'])) {
      return CoachTopic.followUpMenu;
    }

    // Vague follow-ups inherit the last concrete topic.
    if (_isVagueFollowUp(lower)) {
      final prior = _lastConcreteTopic(priorUserQuestions);
      if (prior != null) return prior;
    }

    // Training / drills first when the user clearly wants a workout.
    if (_matches(lower, [
      'give me a workout',
      'create workout',
      'training plan',
      'practice plan',
      'what should i practice',
      'practice today',
      'train today',
      'what to practice',
      "today's workout",
      'todays workout',
      'what should i work on',
      'workout',
      'routine',
      'pregame',
      'generate drills',
      'shooting drills',
      'drills',
      'drill',
      'exercises',
    ])) {
      // "What drill helps that?" after a release talk stays on release,
      // but still answered with a drill-focused coaching card.
      if (_isVagueFollowUp(lower)) {
        final prior = _lastConcreteTopic(priorUserQuestions);
        if (prior != null && prior != CoachTopic.training) return prior;
      }
      return CoachTopic.training;
    }

    if (_matches(lower, [
      'how do i improve',
      'how can i improve',
      'improve my shot',
      'get better',
      'what should i fix',
      'what do i need to improve',
      'how do i get better',
    ])) {
      return CoachTopic.howToImprove;
    }

    if (_matches(lower, [
      'my score',
      'my analysis',
      'my progress',
      'weakness',
      'strength',
      'my shot',
    ])) {
      return CoachTopic.progress;
    }

    if (_matches(lower, [
      'elbow',
      'alignment',
      'shot pocket',
      'set point',
      'inconsistent',
      'consistency',
      'form',
      'mechanics',
      'follow through',
      'follow-through',
      'wrist',
      'guide hand',
      'thumb flick',
      'release feel weird',
      'feels weird',
    ])) {
      // Follow-through / weird release often maps to form mechanics.
      if (_matches(lower, [
            'release',
            'faster',
            'quicker',
            'slow',
            'let go',
            'timing',
          ]) &&
          !_matches(lower, [
            'feel weird',
            'feels weird',
            'follow through',
            'follow-through',
            'elbow',
            'inconsistent',
          ])) {
        return CoachTopic.release;
      }
      return CoachTopic.formMechanics;
    }

    if (_matches(lower, [
      'release',
      'thumb flick',
      'thumb',
      'flick',
      'faster shot',
      'shoot faster',
      'quicker',
      'too slow',
      'release is too slow',
      'when should i let go',
      'let go of the ball',
      'timing',
    ])) {
      return CoachTopic.release;
    }

    if (_matches(lower, [
      'arc',
      'trajectory',
      'rainbow',
      'always short',
      'shots are short',
      'more arc',
      'flat shot',
      'too flat',
    ])) {
      return CoachTopic.arc;
    }

    if (_matches(lower, [
      'fall forward',
      'falling forward',
      'fading away',
      'fade away',
      'fadeaway',
      'balance',
      'stance',
      'base',
      'lean',
    ])) {
      // Pure fadeaway shot-type questions stay in shotTypes when framed as a move.
      if (_matches(lower, ['step back', 'step-back', 'how do i shoot a fade'])) {
        return CoachTopic.shotTypes;
      }
      return CoachTopic.balance;
    }

    if (_matches(lower, [
      'range',
      'deeper',
      'deep',
      'distance',
      'from deep',
      'more power',
      'get more power',
      'increase range',
    ])) {
      return CoachTopic.range;
    }

    if (_matches(lower, [
      'footwork',
      'off the dribble',
      'off-the-dribble',
      'feet feel',
      'awkward feet',
      'my feet',
      '1-2 step',
      'gather',
    ])) {
      return CoachTopic.footwork;
    }

    if (_matches(lower, [
      'mental',
      'confidence',
      'confident',
      'nervous',
      'pressure',
      'under pressure',
      'game prep',
      'prepare',
      'focus',
      'clutch',
    ])) {
      return CoachTopic.mental;
    }

    if (_matches(lower, [
      'free throw',
      'free-throw',
      'ft ',
      'foul shot',
    ])) {
      return CoachTopic.freeThrows;
    }

    if (_matches(lower, [
      'three',
      '3-point',
      '3 point',
      '3pt',
      'beyond the arc',
    ])) {
      return CoachTopic.threes;
    }

    if (_matches(lower, [
      'mid-range',
      'midrange',
      'mid range',
      'pull-up',
      'pull up',
    ])) {
      return CoachTopic.midrange;
    }

    if (_matches(lower, [
      'step back',
      'step-back',
      'dribble',
      'catch and shoot',
      'catch-and-shoot',
      'floater',
      'finish',
      'rim',
      'layup',
    ])) {
      return CoachTopic.shotTypes;
    }

    if (_matches(lower, ['recover', 'soreness', 'ice', 'rest', 'fatigue'])) {
      return CoachTopic.recovery;
    }

    if (_matches(lower, [
      'nba',
      'wnba',
      'ncaa',
      'college',
      'curry',
      'steph',
      'pro',
      'youth',
    ])) {
      return CoachTopic.levels;
    }

    return CoachTopic.general;
  }

  static String reply({
    required String question,
    required AiCoachPersonalization personalization,
    List<String> priorUserQuestions = const [],
  }) {
    final q = question.trim();
    if (q.isEmpty) {
      return 'Ask me anything about shooting mechanics, drills, workouts, '
          'or game prep.';
    }

    final topic = classify(q, priorUserQuestions: priorUserQuestions);
    if (topic == CoachTopic.offTopic) return offTopicRedirect;

    final lower = q.toLowerCase();
    final wantsDrill = _matches(lower, [
      'drill',
      'drills',
      'workout',
      'practice',
      'exercise',
      'what helps',
      'helps that',
    ]);
    final priorTopic = _lastConcreteTopic(priorUserQuestions);
    final isFollowUp = priorUserQuestions.isNotEmpty &&
        (_isVagueFollowUp(lower) || (priorTopic != null && priorTopic == topic));

    switch (topic) {
      case CoachTopic.followUpMenu:
        return _followUpPrompt(personalization);
      case CoachTopic.release:
        return _coachCard(
          personalization: personalization,
          title: 'Release',
          problem: _releaseProblem(personalization, lower),
          why: 'Late or rushed releases usually come from starting the arms '
              'before the legs finish, or holding the ball too long at set point.',
          fix: 'Load the legs, rise in one motion, and let the ball go near the '
              'top of your jump — guide hand quiet, no thumb flick.',
          drill: 'Jump-and-hold × 15 (pause at peak, then release), then remove '
              'the pause for 20 rhythm makes.',
          cue: 'Up and through',
          wantsDrillFocus: wantsDrill,
          followUp: isFollowUp,
          priorTopicLabel: priorTopic == CoachTopic.release ? 'release' : null,
        );
      case CoachTopic.arc:
        return _coachCard(
          personalization: personalization,
          title: 'Arc',
          problem: _arcProblem(personalization, lower),
          why: 'Flat or short shots usually mean the finish is low or power is '
              'coming from the arms instead of the legs.',
          fix: 'Bend the knees, keep a slightly higher set point, snap the wrist '
              'forward and up, and hold a high goose-neck finish.',
          drill: 'Soft-touch form shots from 8 feet — “swish only.” If it rims '
              'hard, raise the finish.',
          cue: 'Finish above the rim',
          wantsDrillFocus: wantsDrill,
          followUp: isFollowUp,
        );
      case CoachTopic.balance:
        return _coachCard(
          personalization: personalization,
          title: 'Balance',
          problem: _balanceProblem(personalization, lower),
          why: 'Falling forward or fading away usually means your base is '
              'shifting during the gather, or your chest is leaning into the shot.',
          fix: 'Feet shoulder-width, shooting-side toe slightly ahead, jump and '
              'land in the same footprint with a quiet chest.',
          drill: 'Stance holds — freeze your base 2 seconds before every shot, '
              'then 1-2 step into catch-and-shoot × 20.',
          cue: 'Quiet feet, quiet chest',
          wantsDrillFocus: wantsDrill,
          followUp: isFollowUp,
        );
      case CoachTopic.range:
        return _coachCard(
          personalization: personalization,
          title: 'Range',
          problem: 'You want more depth or power without breaking form.',
          why: 'Range comes from legs and rhythm. Muscling with the arms flattens '
              'arc and wrecks consistency.',
          fix: 'Perfect form close, then step back one shoe length at a time. '
              'If form breaks, move closer immediately.',
          drill: 'Form-to-range ladder: 10 makes close → step back → 8 makes → '
              'repeat until game distance.',
          cue: 'Legs first',
          wantsDrillFocus: wantsDrill,
          followUp: isFollowUp,
        );
      case CoachTopic.footwork:
        return _coachCard(
          personalization: personalization,
          title: 'Footwork',
          problem: _footworkProblem(lower),
          why: 'Awkward feet usually mean the gather and the shot are fighting '
              'each other — you are creating the shot while still moving.',
          fix: 'Separate space from the shot: gather low, plant a balanced base, '
              'then rise straight. Same 1-2 into every catch-and-shoot.',
          drill: 'Alternate 10 catch-and-shoot / 10 one-dribble pull-ups. Film '
              'your feet — land where you jumped.',
          cue: 'Plant, then rise',
          wantsDrillFocus: wantsDrill,
          followUp: isFollowUp,
        );
      case CoachTopic.formMechanics:
        return _coachCard(
          personalization: personalization,
          title: 'Form mechanics',
          problem: _formProblem(personalization, lower),
          why: _formWhy(lower),
          fix: _formFix(lower),
          drill: _formDrill(lower),
          cue: _formCue(lower),
          wantsDrillFocus: wantsDrill,
          followUp: isFollowUp,
        );
      case CoachTopic.mental:
        return _coachCard(
          personalization: personalization,
          title: 'Mental game',
          problem: 'You want a more confident, repeatable shot under pressure.',
          why: 'Pressure multiplies whatever cue is loudest in your head. Too many '
              'technical thoughts freeze the release.',
          fix: 'Pick one cue word. After a miss, next-action thought only — never '
              'two mechanics at once.',
          drill: 'Pregame: 5 min form makes → 10 hot-spot catch-and-shoot → 10 '
              'free throws with full routine → one visualization with your cue.',
          cue: 'Through',
          wantsDrillFocus: wantsDrill,
          followUp: isFollowUp,
        );
      case CoachTopic.training:
        if (_matches(lower, [
          'workout',
          'create workout',
          'training plan',
          'practice plan',
          'give me a workout',
          'routine',
          'pregame',
        ]) &&
            !_matches(lower, ['drill', 'drills'])) {
          return _workout(personalization);
        }
        if (_matches(lower, [
          'what should i practice',
          'practice today',
          'train today',
          'what to practice',
          "today's workout",
          'todays workout',
          'what should i work on',
        ])) {
          return TrainingDrillsService.practiceTodayReply(personalization);
        }
        return _drills(personalization, wantsDrill || isFollowUp);
      case CoachTopic.howToImprove:
        return _howToImprove(personalization, isFollowUp);
      case CoachTopic.progress:
        return _personalProgress(personalization, isFollowUp);
      case CoachTopic.freeThrows:
        return _freeThrows(personalization, isFollowUp);
      case CoachTopic.threes:
        return _threes(personalization, isFollowUp);
      case CoachTopic.midrange:
        return _midrange(personalization, isFollowUp);
      case CoachTopic.shotTypes:
        return _shotTypes(personalization, lower, isFollowUp);
      case CoachTopic.recovery:
        return _recovery(personalization, isFollowUp);
      case CoachTopic.levels:
        return _levels(personalization, lower, isFollowUp);
      case CoachTopic.offTopic:
        return offTopicRedirect;
      case CoachTopic.general:
        return _general(personalization, q, isFollowUp, priorTopic);
    }
  }

  static bool _matches(String q, List<String> keys) =>
      keys.any((k) => q.contains(k));

  static bool _isVagueFollowUp(String lower) {
    if (_matches(lower, [
      'what drill',
      'which drill',
      'drill for that',
      'drills for that',
      'helps that',
      'help with that',
      'same thing',
      'that issue',
      'that problem',
      'more detail',
      'explain more',
      'tell me more',
      'go deeper',
      'and then',
      'what about that',
      'how do i fix that',
      'fix that',
      'why does that',
    ])) {
      return true;
    }
    // Very short follow-ups: "why?", "how?", "drills?", "more"
    final words = lower
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.length <= 3 &&
        _matches(lower, [
          'more',
          'why',
          'how',
          'again',
          'drill',
          'drills',
          'that',
          'this',
          'ok',
          'okay',
          'yes',
          'yeah',
        ])) {
      return true;
    }
    return false;
  }

  static CoachTopic? _lastConcreteTopic(List<String> prior) {
    for (final q in prior.reversed) {
      final t = classify(q, priorUserQuestions: const []);
      if (t == CoachTopic.offTopic ||
          t == CoachTopic.general ||
          t == CoachTopic.followUpMenu) {
        continue;
      }
      // Skip vague-only reclassify by using empty prior above.
      if (_isVagueFollowUp(q.toLowerCase())) continue;
      return t;
    }
    return null;
  }

  static String _coachCard({
    required AiCoachPersonalization personalization,
    required String title,
    required String problem,
    required String why,
    required String fix,
    required String drill,
    required String cue,
    bool wantsDrillFocus = false,
    bool followUp = false,
    String? priorTopicLabel,
  }) {
    final buf = StringBuffer()
      ..write(_athleteLine(personalization))
      ..write(_personalLead(personalization));

    if (followUp && priorTopicLabel != null) {
      buf.writeln(
        '_Still on **$priorTopicLabel** from your last question._\n',
      );
    } else if (followUp) {
      buf.writeln('_Building on what we just covered._\n');
    }

    if (wantsDrillFocus) {
      buf
        ..writeln('### Drill for $title')
        ..writeln()
        ..writeln('**Problem:** $problem')
        ..writeln()
        ..writeln('**Drill:** $drill')
        ..writeln()
        ..writeln('**Fix to keep in mind:** $fix')
        ..writeln()
        ..writeln('Cue: *"$cue"*');
      return buf.toString().trim();
    }

    buf
      ..writeln('### $title')
      ..writeln()
      ..writeln('**Problem:** $problem')
      ..writeln()
      ..writeln('**Why:** $why')
      ..writeln()
      ..writeln('**Fix:** $fix')
      ..writeln()
      ..writeln('**Drill:** $drill')
      ..writeln()
      ..writeln('Cue: *"$cue"*');
    return buf.toString().trim();
  }

  static String _releaseProblem(AiCoachPersonalization p, String lower) {
    if (_matches(lower, ['faster', 'quicker', 'slow', 'too slow'])) {
      return 'Your release is slower than you want — the gather is taking too long.';
    }
    if (_matches(lower, ['let go', 'when should'])) {
      return 'Timing the release — when to let the ball go — is unclear.';
    }
    if (p.releaseImproving) {
      return 'Release timing is trending up, but it still needs to stay consistent at game speed.';
    }
    if (p.weaknesses.any((w) => w.toLowerCase().contains('release'))) {
      return 'Release timing is showing up as a weakness in your recent analyses.';
    }
    return 'Your release needs to be cleaner and more repeatable.';
  }

  static String _arcProblem(AiCoachPersonalization p, String lower) {
    if (_matches(lower, ['short', 'always short'])) {
      return 'Your shots are finishing short — the ball is not getting enough soft arc.';
    }
    if (p.weaknesses.any((w) =>
        w.toLowerCase().contains('arc') || w.toLowerCase().contains('knee'))) {
      return 'Arc / leg load is a recurring limiter in your recent analyses.';
    }
    return 'You need more consistent arc without floating the shot.';
  }

  static String _balanceProblem(AiCoachPersonalization p, String lower) {
    if (_matches(lower, ['fall forward', 'falling forward'])) {
      return 'You are falling forward on the shot — your momentum is leaking toward the rim.';
    }
    if (_matches(lower, ['fading', 'fade away', 'fadeaway'])) {
      return 'You are fading away — the base is drifting back instead of rising straight.';
    }
    if (p.weaknesses.any((w) => w.toLowerCase().contains('balance'))) {
      return 'Balance is a recurring focus area in your recent analyses.';
    }
    return 'Your base is not staying quiet through the shot.';
  }

  static String _footworkProblem(String lower) {
    if (_matches(lower, ['off the dribble', 'off-the-dribble', 'dribble'])) {
      return 'Shooting off the dribble feels rushed or off-balance.';
    }
    if (_matches(lower, ['awkward', 'feet feel'])) {
      return 'Your feet feel awkward going into the shot.';
    }
    return 'Footwork into the shot needs to be cleaner and more repeatable.';
  }

  static String _formProblem(AiCoachPersonalization p, String lower) {
    if (_matches(lower, ['elbow'])) {
      if (p.elbowStillWeak) {
        return 'Your elbow keeps drifting — and recent analyses still flag elbow alignment.';
      }
      return 'Your elbow keeps moving out / losing alignment under the ball.';
    }
    if (_matches(lower, ['inconsistent', 'consistency'])) {
      final weak =
          p.weaknesses.isNotEmpty ? p.weaknesses.first : 'release timing';
      return 'Your shot feels inconsistent — usually that traces back to **$weak**.';
    }
    if (_matches(lower, ['follow through', 'follow-through', 'wrist'])) {
      return 'Your follow-through is breaking down — the finish is not holding.';
    }
    if (_matches(lower, ['weird', 'feel'])) {
      return 'Your release feels off — something in the pocket-to-finish path is changing.';
    }
    if (p.weaknesses.isNotEmpty) {
      return 'Form mechanics around **${p.weaknesses.first}** need cleanup.';
    }
    return 'Your shooting form has a mechanical leak that is costing consistency.';
  }

  static String _formWhy(String lower) {
    if (_matches(lower, ['elbow'])) {
      return 'When the shooting arm loses alignment, the ball starts offline and '
          'your release has to compensate.';
    }
    if (_matches(lower, ['inconsistent', 'consistency'])) {
      return 'Inconsistency almost always means the pocket, elbow path, or release '
          'point is changing from shot to shot.';
    }
    if (_matches(lower, ['follow through', 'follow-through', 'wrist'])) {
      return 'A short or sideways finish usually means the guide hand is interfering '
          'or you are dropping the shooting hand early.';
    }
    return 'Small setup changes compound — elbow, pocket, and finish have to look '
        'the same every rep.';
  }

  static String _formFix(String lower) {
    if (_matches(lower, ['elbow'])) {
      return 'Keep your shooting elbow stacked under the ball and tracking toward the rim.';
    }
    if (_matches(lower, ['follow through', 'follow-through', 'wrist'])) {
      return 'Snap fingers at the target and freeze a high goose-neck until the ball lands.';
    }
    return 'Lock one cue for the whole session — pocket, elbow under the ball, high finish.';
  }

  static String _formDrill(String lower) {
    if (_matches(lower, ['elbow'])) {
      return '50 form shots close to the basket — elbow under the ball on every rep. '
          'Add wall-touch set points if it still flares.';
    }
    if (_matches(lower, ['follow through', 'follow-through', 'wrist'])) {
      return '25 one-hand form makes with a frozen finish. If spin goes sideways, '
          'the guide hand is the problem.';
    }
    return '25 perfect-form makes inside 10 feet with one cue only. Film the last 5.';
  }

  static String _formCue(String lower) {
    if (_matches(lower, ['elbow'])) return 'Elbow to the rim';
    if (_matches(lower, ['follow through', 'follow-through', 'wrist'])) {
      return 'Hold the finish';
    }
    return 'Same pocket every catch';
  }

  static String _personalLead(AiCoachPersonalization p) {
    final smart = p.smartContextLead();
    if (smart.isEmpty) return '';
    return '$smart\n\n';
  }

  static String _howToImprove(AiCoachPersonalization p, bool followUp) {
    final buf = StringBuffer()
      ..write(_athleteLine(p))
      ..write(_personalLead(p));

    if (!p.hasAnalyses) {
      buf.writeln(
        'Analyze a few shots first so I can coach from your real mechanics — '
        'not generic tips.',
      );
      buf.writeln();
      buf.writeln(
        'Start with side-angle film, full body in frame, one clean jumper.',
      );
      return buf.toString().trim();
    }

    final releasePts = p.releaseTrendPoints;
    final weak = p.weaknesses.isNotEmpty ? p.weaknesses.first : 'release timing';

    buf
      ..writeln('### How to improve')
      ..writeln();

    if (p.releaseImproving && p.elbowStillWeak) {
      buf.writeln(
        '**Problem:** Your last shots show release timing improving'
        '${releasePts != null ? ' (~**$releasePts** points)' : ''}, '
        'but **elbow alignment** is still your biggest weakness.',
      );
      buf.writeln();
      buf.writeln(
        '**Why:** A cleaner release cannot fully save a flared elbow — the ball '
        'still starts offline.',
      );
      buf.writeln();
      buf.writeln(
        '**Fix:** Keep your shooting elbow stacked under the ball on every catch.',
      );
      buf.writeln();
      buf.writeln(
        '**Drill:** 50 form shots close to the basket — elbow under the ball, '
        'same pocket every rep.',
      );
    } else if (p.weaknesses.isNotEmpty) {
      buf.writeln(
        '**Problem:** Across your last ${p.shots.take(10).length} shots, '
        '**$weak** is the clearest limiter.',
      );
      buf.writeln();
      buf.writeln(
        '**Why:** That category is costing you the most repeatability right now.',
      );
      buf.writeln();
      buf.writeln(
        '**Fix:** Make **$weak** the only cue for your next session.',
      );
      buf.writeln();
      buf.writeln(
        '**Drill:** Film 10 focused reps on $weak, then compare the next '
        'analysis to this week’s average.',
      );
    } else {
      buf.writeln(
        '**Problem:** Your recent form is balanced — the upside is consistency '
        'at game speed.',
      );
      buf.writeln();
      buf.writeln(
        '**Why:** Clean mechanics still break down when pace and pressure rise.',
      );
      buf.writeln();
      buf.writeln(
        '**Fix:** Keep one cue and transfer it to catch-and-shoot + pull-ups.',
      );
      buf.writeln();
      buf.writeln(
        '**Drill:** 10 form → 10 catch-and-shoot → 10 one-dribble pull-ups.',
      );
    }

    final skill = (p.skillLevel ?? '').toLowerCase();
    if (skill.contains('beginner') || skill.contains('youth')) {
      buf
        ..writeln()
        ..writeln(
          'Beginner standard: perfect form inside 10 feet before you chase range.',
        );
    } else if (skill.contains('advanced') || skill.contains('elite')) {
      buf
        ..writeln()
        ..writeln(
          'Advanced standard: the same cue must hold on catch-and-shoot and pull-ups.',
        );
    }

    if (p.dominantHand != null) {
      buf
        ..writeln()
        ..writeln(
          'Lock the ${p.dominantHand!.toLowerCase()}-hand pocket — same set every catch.',
        );
    }

    if (p.goal != null && p.goal!.isNotEmpty) {
      buf
        ..writeln()
        ..writeln('Tied to your goal (**${p.goal}**): keep tomorrow’s session on this same limiter.');
    }

    buf
      ..writeln()
      ..writeln(
        'Ask *What should I practice today?* for a full session, or open your '
        'latest Results report for “Why You Lost Points.”',
      );
    return buf.toString().trim();
  }

  static String _athleteLine(AiCoachPersonalization p) {
    final bits = <String>[
      if (p.skillLevel != null) p.skillLevel!,
      if (p.position != null) p.position!,
      if (p.dominantHand != null) '${p.dominantHand} hand',
    ];
    if (bits.isEmpty) return '';
    return '_Coaching for: ${bits.join(' · ')}_\n\n';
  }

  static String _followUpPrompt(AiCoachPersonalization p) {
    final focus = p.weaknesses.isNotEmpty
        ? p.weaknesses.first
        : 'your release timing';
    return '${_athleteLine(p)}'
        'Great — let’s go deeper on **$focus**.\n\n'
        'What do you want next?\n'
        '1. A 10-minute drill block\n'
        '2. Film cues to watch for\n'
        '3. A full workout for tomorrow\n\n'
        'Reply with 1, 2, or 3 — or tell me the exact issue you feel on the court.';
  }

  static String _drills(AiCoachPersonalization p, bool followUp) {
    final primary = TrainingDrillsService.primaryAiDrill(p);
    final ranked = TrainingDrillsService.personalizedDrills(p, limit: 3);
    final buf = StringBuffer()
      ..write(_athleteLine(p))
      ..write(_personalLead(p))
      ..writeln('### Personalized shooting drills')
      ..writeln()
      ..writeln('**Problem:** ${primary.problem}')
      ..writeln()
      ..writeln('**Drill:** **${primary.title}** · ${primary.durationLabel}')
      ..writeln();
    for (var i = 0; i < primary.instructions.length; i++) {
      buf.writeln('${i + 1}. ${primary.instructions[i]}');
    }
    buf
      ..writeln()
      ..writeln('Reps: ${primary.reps}')
      ..writeln()
      ..writeln('### Also recommended');
    for (final drill in ranked.skip(1)) {
      buf.writeln(
        '- **${drill.title}** (${drill.durationLabel}) — ${drill.problem}',
      );
    }
    buf
      ..writeln()
      ..writeln(
        'Open **Drills** for the full library + 15/30/60 minute workout builder.',
      );
    if (followUp) {
      buf.writeln(
        '\nWant a full session? Ask *What should I practice today?*',
      );
    }
    return buf.toString().trim();
  }

  static String _topicLabel(CoachTopic topic) {
    switch (topic) {
      case CoachTopic.release:
        return 'Fix my release';
      case CoachTopic.arc:
        return 'Improve my arc';
      case CoachTopic.balance:
        return 'Better balance';
      case CoachTopic.range:
        return 'Increase my range';
      case CoachTopic.footwork:
        return 'How do I shoot off the dribble?';
      case CoachTopic.formMechanics:
        return 'My elbow keeps moving out';
      case CoachTopic.mental:
        return 'How do I shoot better under pressure?';
      case CoachTopic.freeThrows:
        return 'Help with free throws';
      case CoachTopic.threes:
        return 'Help with three point shooting';
      case CoachTopic.midrange:
        return 'Help with mid-range';
      default:
        return 'Fix my release';
    }
  }

  static String _freeThrows(AiCoachPersonalization p, bool followUp) {
    return _coachCard(
      personalization: p,
      title: 'Free throws',
      problem: 'Free throws need a routine that holds under fatigue.',
      why: 'Missed free throws are usually broken routine or rushed legs — not a new form.',
      fix: 'Build a 5-step routine: feet → dribbles → breath → eyes on back rim → '
          'one-motion shot + hold finish. Never change it.',
      drill: 'Make-based ladder: 2, 4, 6, 8, 10 straight — or leave only after 10 in a row.',
      cue: 'Same routine',
      followUp: followUp,
    );
  }

  static String _threes(AiCoachPersonalization p, bool followUp) {
    return _coachCard(
      personalization: p,
      title: 'Three-point shooting',
      problem: 'Deep shots are inconsistent when rhythm or legs drop out.',
      why: 'Threes demand legs and rhythm. Muscling them flattens arc.',
      fix: 'Form inside the arc → mid-range → catch-and-shoot threes by spot. '
          'Off-dribble threes only after catch-and-shoot is clean.',
      drill: 'Corners → wings → top: 8 attempts each. Track makes by spot; weakest '
          'spot opens tomorrow’s session.',
      cue: 'Legs and rhythm',
      followUp: followUp,
    );
  }

  static String _midrange(AiCoachPersonalization p, bool followUp) {
    return _coachCard(
      personalization: p,
      title: 'Mid-range scoring',
      problem: 'Mid-range makes depend on footwork more than arm strength.',
      why: 'Rushed gathers and drifting bases are why elbow jumpers come and go.',
      fix: 'Square early on catch-and-shoot. On pull-ups: 1-2 step, gather low, rise straight.',
      drill: 'Elbow jumpers — 5 makes each side before you leave.',
      cue: 'Square early',
      followUp: followUp,
    );
  }

  static String _shotTypes(
    AiCoachPersonalization p,
    String lower,
    bool followUp,
  ) {
    if (_matches(lower, ['floater', 'finish', 'rim', 'layup'])) {
      return _coachCard(
        personalization: p,
        title: 'Finishing & floaters',
        problem: 'Around the rim, touch is breaking down under contact or help.',
        why: 'Power takes over when you rush — soft fingers and angle win finishes.',
        fix: 'Protect with the off-arm, aim soft touch to the top corner on banks, '
            'and scoop floaters high on the way up.',
        drill: 'Mikan + reverse Mikan × 20, then 10 floaters each side.',
        cue: 'Touch over power',
        followUp: followUp,
      );
    }
    if (_matches(lower, ['step back', 'step-back', 'fadeaway', 'fade'])) {
      return _coachCard(
        personalization: p,
        title: 'Step-backs & fadeaways',
        problem: 'You are trying to create space and shoot in the same motion.',
        why: 'When space and release overlap, balance dies and the ball starts short or side.',
        fix: 'Create space first, land balanced, then rise. Fade after the gather — '
            'keep shoulders as square as possible.',
        drill: '10 step-backs focusing on plant-then-shot, then 10 straight-up jumpers.',
        cue: 'Space, then shot',
        followUp: followUp,
      );
    }
    return _coachCard(
      personalization: p,
      title: 'Off-the-dribble & catch-and-shoot',
      problem: 'Movement shooting is less consistent than your standstill form.',
      why: 'The gather changes your pocket and base if you do not prepare early.',
      fix: 'Catch-and-shoot: hands ready, feet set early, same pocket. '
          'Off-dribble: low gather, eyes up, rise straight.',
      drill: 'Alternate 10 catch-and-shoot / 10 one-dribble pull-ups.',
      cue: 'Ready early',
      followUp: followUp,
    );
  }

  static String _recovery(AiCoachPersonalization p, bool followUp) {
    return '${_athleteLine(p)}'
        '### Recovery for shooters\n\n'
        '**Problem:** Volume without recovery flattens arc and release.\n\n'
        '**Why:** Tired legs and sore wrists change timing before you notice.\n\n'
        '**Fix:** Sleep 7–9 hours when possible, keep ankle/hip/T-spine mobility, '
        'and alternate heavy shooting days with form days.\n\n'
        '**Drill:** On sore days, cut volume 40% and keep form work only inside '
        'the lane.\n\n'
        'Hydrate and eat protein after long sessions — tomorrow’s touch depends on it.';
  }

  static String _levels(
    AiCoachPersonalization p,
    String lower,
    bool followUp,
  ) {
    if (_matches(lower, ['youth'])) {
      return '${_athleteLine(p)}'
          '### Youth player development\n\n'
          '**Problem:** Young shooters chase distance before form is stable.\n\n'
          '**Why:** Growth spurts and early threes wreck timing.\n\n'
          '**Fix:** Prioritize form, balance, and follow-through before range.\n\n'
          '**Drill:** Lots of makes close to the basket — 20–30 minute fun sessions.';
    }
    if (_matches(lower, ['wnba'])) {
      return '${_athleteLine(p)}'
          '### WNBA shooting habits to steal\n\n'
          '**Problem:** You want pro-level readiness on catch-and-shoot looks.\n\n'
          '**Why:** Elite shooters win with footwork, balance, and repeatable pockets.\n\n'
          '**Fix:** Prepare early, keep a compact release, strong base on movement threes.\n\n'
          '**Drill:** Study a player at your position and copy their gather footwork for 15 minutes.';
    }
    if (_matches(lower, ['ncaa', 'college'])) {
      return '${_athleteLine(p)}'
          '### NCAA-level shooting standards\n\n'
          '**Problem:** College pace exposes slow decisions and soft free-throw routines.\n\n'
          '**Why:** Contested windows and fatigue punish hitchy gathers.\n\n'
          '**Fix:** Consistent FT routine, spot-up readiness in transition, conditioned makes.\n\n'
          '**Drill:** Catch → shoot / drive / pass decisions in under one second × 20 reps.';
    }
    return _coachCard(
      personalization: p,
      title: 'Pro shooting model',
      problem: 'You want a more pro-like, repeatable jumper.',
      why: 'Pros share identical pockets, one-motion rise, high finishes, and balanced footwork.',
      fix: 'Copy repeatability first — not deep range. Same pocket every catch.',
      drill: 'Hold your finish on every make in practice this week. Film 10 reps side-angle.',
      cue: 'Same shot every time',
      followUp: followUp,
    );
  }

  static String _personalProgress(AiCoachPersonalization p, bool followUp) {
    if (!p.hasAnalyses) {
      return 'You do not have saved shot analyses yet.\n\n'
          'Tap **Analyze My Shot** to upload or record a session. '
          'Once ShootIQ has a few results, I can reference your average score, '
          'strengths, and weaknesses automatically.';
    }

    final avg = p.averageScore?.round() ?? 0;
    final recent = p.recentScores.join(', ');
    final strengths =
        p.strengths.isEmpty ? 'developing consistency' : p.strengths.join(', ');
    final weaknesses =
        p.weaknesses.isEmpty ? 'overall polish' : p.weaknesses.join(', ');

    return '${_athleteLine(p)}'
        '### Your ShootIQ snapshot\n\n'
        '- **Analyses:** ${p.shots.length}\n'
        '- **Average score:** $avg\n'
        '- **Recent scores:** $recent\n'
        '- **Strengths:** $strengths\n'
        '- **Focus areas:** $weaknesses\n'
        '${p.goal != null ? '- **Goal:** ${p.goal}\n' : ''}'
        '\n'
        '${p.smartContextLead().isNotEmpty ? '${p.smartContextLead()}\n\n' : ''}'
        'Ask me for drills targeting your weakest category, or tap **Generate Drills**.';
  }

  static String _general(
    AiCoachPersonalization p,
    String question,
    bool followUp,
    CoachTopic? priorTopic,
  ) {
    // Numbered menu replies after "Ask follow-up"
    final lower = question.toLowerCase().trim();
    if (lower == '1' || lower.startsWith('1.') || lower == 'one') {
      return _drills(p, true);
    }
    if (lower == '2' || lower.startsWith('2.') || lower == 'two') {
      return _coachCard(
        personalization: p,
        title: 'Film cues',
        problem: p.weaknesses.isNotEmpty
            ? 'You need clear film cues for **${p.weaknesses.first}**.'
            : 'You need clear film cues for your next session.',
        why: 'Without a visual checklist, you cannot tell if the fix is sticking.',
        fix: 'Side angle, full body, same spot. Watch pocket → elbow → release → land.',
        drill: 'Film 10 focused reps with one cue, then compare to your last analysis.',
        cue: 'One cue on film',
        followUp: true,
      );
    }
    if (lower == '3' || lower.startsWith('3.') || lower == 'three') {
      return _workout(p);
    }

    if (priorTopic != null && followUp) {
      return reply(
        question: _topicLabel(priorTopic),
        personalization: p,
        priorUserQuestions: [_topicLabel(priorTopic)],
      );
    }

    final weak =
        p.weaknesses.isNotEmpty ? p.weaknesses.first : 'one mechanical cue';

    return '${_athleteLine(p)}${_personalLead(p)}'
        'You asked: “$question”\n\n'
        '**Problem:** I want to coach the exact limiter in that question.\n\n'
        '**Why:** Vague goals create vague sessions.\n\n'
        '**Fix:** Pick **one** cue for the next block'
        '${p.hasAnalyses ? ' — start with **$weak**' : ''}.\n\n'
        '**Drill:** Earn makes close to the basket with that cue, then step into '
        'game speed only after form is clean. Finish with free throws.\n\n'
        'Try asking about release, arc, balance, range, footwork, confidence, '
        'or type anything about your shot — I will classify it and coach from there.';
  }

  static String _workout(AiCoachPersonalization p) {
    final workout = TrainingDrillsService.buildWorkout(
      personalization: p,
      minutes: 30,
    );
    final buf = StringBuffer()
      ..write(_athleteLine(p))
      ..write(_personalLead(p))
      ..writeln('### ${workout.title}')
      ..writeln()
      ..writeln(workout.summary)
      ..writeln()
      ..writeln('**Warmup**');
    for (final d in workout.warmup) {
      buf.writeln('- ${d.title} (${d.durationLabel})');
    }
    buf.writeln('\n**Main drills**');
    for (final d in workout.mainDrills) {
      buf.writeln('- **${d.title}** (${d.durationLabel}) — ${d.reps}');
    }
    buf.writeln('\n**Cool down**');
    for (final d in workout.cooldown) {
      buf.writeln('- ${d.title} (${d.durationLabel})');
    }
    buf
      ..writeln()
      ..writeln(
        'Open **Drills** to switch between 15, 30, or 60 minute builders.',
      );
    return buf.toString().trim();
  }
}
