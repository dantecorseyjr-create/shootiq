import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:go_router/go_router.dart';
import 'package:shootiq/config/theme.dart';
import 'package:shootiq/models/ai_coach_message.dart';
import 'package:shootiq/router/app_router.dart';
import 'package:shootiq/services/ai_coach_history_store.dart';
import 'package:shootiq/services/ai_coach_personalization.dart';
import 'package:shootiq/services/ai_coach_service.dart';
import 'package:shootiq/services/subscription_service.dart';

class AiCoachPage extends StatefulWidget {
  const AiCoachPage({super.key});

  @override
  State<AiCoachPage> createState() => _AiCoachPageState();
}

class _AiCoachPageState extends State<AiCoachPage>
    with TickerProviderStateMixin {
  static const _suggestions = [
    'Fix my release',
    'Improve my arc',
    'Increase range',
    'Better balance',
    'Shooting drills',
    'What should I practice today?',
    'Create workout',
    'Pregame routine',
  ];

  late final AnimationController _fadeController;
  late final AnimationController _typingController;
  late final Animation<double> _fadeAnimation;
  late final TextEditingController _inputController;
  late final ScrollController _scrollController;
  late final FocusNode _inputFocus;

  final List<AiCoachMessage> _messages = [];
  final List<String> _priorUserQuestions = [];

  AiCoachPersonalization _personalization = const AiCoachPersonalization();
  bool _loadingHistory = true;
  bool _isTyping = false;
  bool _isStreaming = false;
  String _streamingText = '';
  Timer? _streamTimer;
  bool _savingSnackVisible = false;

  bool get _hasConversation => _messages.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _inputController = TextEditingController();
    _scrollController = ScrollController();
    _inputFocus = FocusNode();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _typingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();

    _fadeController.forward();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final results = await Future.wait([
      AiCoachHistoryStore.load(),
      AiCoachPersonalization.load(),
    ]);
    if (!mounted) return;
    setState(() {
      _messages
        ..clear()
        ..addAll(results[0] as List<AiCoachMessage>);
      _personalization = results[1] as AiCoachPersonalization;
      _priorUserQuestions.addAll(
        _messages.where((m) => m.isUser).map((m) => m.text),
      );
      _loadingHistory = false;
    });
    if (_messages.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  @override
  void dispose() {
    _streamTimer?.cancel();
    _inputController.dispose();
    _scrollController.dispose();
    _inputFocus.dispose();
    _fadeController.dispose();
    _typingController.dispose();
    super.dispose();
  }

  Future<void> _persist() => AiCoachHistoryStore.save(_messages);

  Future<void> _scrollToBottom() async {
    await Future<void>.delayed(const Duration(milliseconds: 40));
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  Future<void> _sendMessage(String rawText) async {
    final text = rawText.trim();
    if (text.isEmpty || _isTyping || _isStreaming) return;

    final userMessage = AiCoachMessage(
      id: 'u_${DateTime.now().millisecondsSinceEpoch}',
      role: AiCoachMessageRole.user,
      text: text,
      createdAt: DateTime.now(),
    );

    setState(() {
      _messages.add(userMessage);
      _priorUserQuestions.add(text);
      _isTyping = true;
      _inputController.clear();
    });
    await _persist();
    _scrollToBottom();

    // Light delay for typing indicator, then stream the reply.
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;

    final fullReply = AiCoachService.reply(
      question: text,
      personalization: _personalization,
      priorUserQuestions:
          List<String>.from(_priorUserQuestions)..removeLast(),
    );

    setState(() {
      _isTyping = false;
      _isStreaming = true;
      _streamingText = '';
    });
    _scrollToBottom();
    await _streamReply(fullReply);
  }

  Future<void> _streamReply(String fullText) async {
    _streamTimer?.cancel();
    final words = fullText.split(' ');
    var index = 0;
    final completer = Completer<void>();

    _streamTimer = Timer.periodic(const Duration(milliseconds: 28), (timer) {
      if (!mounted) {
        timer.cancel();
        if (!completer.isCompleted) completer.complete();
        return;
      }

      // Stream a few words at a time for snappy feel.
      final take = (index + 3 < words.length) ? 3 : (words.length - index);
      if (take <= 0) {
        timer.cancel();
        final assistant = AiCoachMessage(
          id: 'a_${DateTime.now().millisecondsSinceEpoch}',
          role: AiCoachMessageRole.assistant,
          text: fullText,
          createdAt: DateTime.now(),
        );
        setState(() {
          _isStreaming = false;
          _streamingText = '';
          _messages.add(assistant);
        });
        _persist();
        _scrollToBottom();
        if (!completer.isCompleted) completer.complete();
        return;
      }

      final chunk = words.sublist(index, index + take).join(' ');
      index += take;
      setState(() {
        _streamingText = _streamingText.isEmpty
            ? chunk
            : '$_streamingText $chunk';
      });
      _scrollToBottom();
    });

    await completer.future;
  }

  void _onQuickAction(String action, AiCoachMessage message) {
    switch (action) {
      case 'Ask Follow-up':
        _sendMessage('Ask follow-up');
      case 'Analyze My Shot':
        // Gate real analysis — free users see Premium, subscribers open camera.
        SubscriptionService.openAnalysisOrPaywall(
          context,
          destination: AppRoutes.camera,
        );
      case 'Generate Drills':
        _sendMessage('Generate drills');
      case 'Create Workout':
        _sendMessage('Create workout');
      case 'Open Drills':
        context.push(AppRoutes.drills);
      case 'Practice Today':
        _sendMessage('What should I practice today?');
      case 'Save Conversation':
        _saveConversation();
    }
  }

  Future<void> _saveConversation() async {
    await _persist();
    if (!mounted || _savingSnackVisible) return;
    _savingSnackVisible = true;
    ScaffoldMessenger.of(context)
        .showSnackBar(
          const SnackBar(
            content: Text('Conversation saved on this device.'),
            backgroundColor: ShootIQTheme.surfaceElevated,
            behavior: SnackBarBehavior.floating,
          ),
        )
        .closed
        .then((_) => _savingSnackVisible = false);
  }

  Future<void> _clearConversation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: ShootIQTheme.cardBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Clear conversation?',
            style: TextStyle(
              color: ShootIQTheme.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: const Text(
            'This removes your saved AI Coach chat history on this device.',
            style: TextStyle(color: ShootIQTheme.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text(
                'Cancel',
                style: TextStyle(color: ShootIQTheme.textSecondary),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text(
                'Clear',
                style: TextStyle(
                  color: ShootIQTheme.errorRed,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    await AiCoachHistoryStore.clear();
    setState(() {
      _messages.clear();
      _priorUserQuestions.clear();
      _streamingText = '';
      _isStreaming = false;
      _isTyping = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Scaffold(
      backgroundColor: ShootIQTheme.darkBackground,
      resizeToAvoidBottomInset: true,
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 12, 0),
                child: _CoachTopBar(
                  hasConversation: _hasConversation,
                  onClear: _hasConversation ? _clearConversation : null,
                  onHistory: _hasConversation ? _saveConversation : null,
                  onOpenDrills: () => context.push(AppRoutes.drills),
                ),
              ),
              Expanded(
                child: _loadingHistory
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: ShootIQTheme.basketballOrange,
                        ),
                      )
                    : !_hasConversation && !_isTyping && !_isStreaming
                        ? _CoachHome(
                            suggestions: _suggestions,
                            personalization: _personalization,
                            onSuggestion: _sendMessage,
                            onFocusInput: () => _inputFocus.requestFocus(),
                          )
                        : _ChatList(
                            messages: _messages,
                            scrollController: _scrollController,
                            isTyping: _isTyping,
                            isStreaming: _isStreaming,
                            streamingText: _streamingText,
                            typingController: _typingController,
                            onQuickAction: _onQuickAction,
                          ),
              ),
              if (!_hasConversation && !_loadingHistory)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: _SuggestionWrap(
                    suggestions: _suggestions,
                    onSelected: _sendMessage,
                  ),
                ),
              _Composer(
                controller: _inputController,
                focusNode: _inputFocus,
                enabled: !_isTyping && !_isStreaming,
                bottomPadding: bottomInset > 0 ? 8 : 10,
                onSend: () => _sendMessage(_inputController.text),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoachTopBar extends StatelessWidget {
  const _CoachTopBar({
    required this.hasConversation,
    this.onClear,
    this.onHistory,
    this.onOpenDrills,
  });

  final bool hasConversation;
  final VoidCallback? onClear;
  final VoidCallback? onHistory;
  final VoidCallback? onOpenDrills;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                ShootIQTheme.basketballOrange,
                ShootIQTheme.basketballOrangeLight,
              ],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.psychology_rounded,
            color: Colors.white,
            size: 22,
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Text(
            'AI Coach',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: ShootIQTheme.textPrimary,
              letterSpacing: -0.4,
            ),
          ),
        ),
        if (onOpenDrills != null)
          IconButton(
            onPressed: onOpenDrills,
            tooltip: 'AI Training Drills',
            icon: const Icon(
              Icons.fitness_center_rounded,
              color: ShootIQTheme.basketballOrange,
            ),
          ),
        if (onHistory != null)
          IconButton(
            onPressed: onHistory,
            tooltip: 'Save conversation',
            icon: const Icon(
              Icons.bookmark_border_rounded,
              color: ShootIQTheme.textSecondary,
            ),
          ),
        if (onClear != null)
          IconButton(
            onPressed: onClear,
            tooltip: 'Clear conversation',
            icon: const Icon(
              Icons.delete_outline_rounded,
              color: ShootIQTheme.textSecondary,
            ),
          ),
      ],
    );
  }
}

class _CoachHome extends StatelessWidget {
  const _CoachHome({
    required this.suggestions,
    required this.personalization,
    required this.onSuggestion,
    required this.onFocusInput,
  });

  final List<String> suggestions;
  final AiCoachPersonalization personalization;
  final ValueChanged<String> onSuggestion;
  final VoidCallback onFocusInput;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 12),
      children: [
        Center(
          child: Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  ShootIQTheme.basketballOrange,
                  ShootIQTheme.basketballOrangeLight,
                  ShootIQTheme.surfaceElevated,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: ShootIQTheme.basketballOrange.withValues(alpha: 0.35),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: const Icon(
              Icons.sports_basketball_rounded,
              color: Colors.white,
              size: 44,
            ),
          ),
        ),
        const SizedBox(height: 28),
        const Text(
          'AI Shooting Coach',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            color: ShootIQTheme.textPrimary,
            letterSpacing: -0.8,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Type any shooting question — or tap a suggestion',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            color: ShootIQTheme.textSecondary,
            height: 1.4,
          ),
        ),
        if (personalization.hasAnalyses) ...[
          const SizedBox(height: 18),
          _PersonalInsightBanner(personalization: personalization),
        ],
        const SizedBox(height: 28),
        GestureDetector(
          onTap: onFocusInput,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
            decoration: BoxDecoration(
              color: ShootIQTheme.cardBackground,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: ShootIQTheme.basketballOrange.withValues(alpha: 0.35),
              ),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.chat_bubble_outline_rounded,
                  color: ShootIQTheme.basketballOrange,
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Ask a shooting question...',
                    style: TextStyle(
                      color: ShootIQTheme.textSecondary,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 22),
        const Text(
          'Suggested prompts',
          style: TextStyle(
            color: ShootIQTheme.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        _SuggestionWrap(
          suggestions: suggestions,
          onSelected: onSuggestion,
        ),
      ],
    );
  }
}

class _PersonalInsightBanner extends StatelessWidget {
  const _PersonalInsightBanner({required this.personalization});

  final AiCoachPersonalization personalization;

  @override
  Widget build(BuildContext context) {
    final avg = personalization.averageScore?.round();
    final weak = personalization.weaknesses.isNotEmpty
        ? personalization.weaknesses.first
        : null;
    final strong = personalization.strengths.isNotEmpty
        ? personalization.strengths.first
        : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ShootIQTheme.basketballOrange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: ShootIQTheme.basketballOrange.withValues(alpha: 0.28),
        ),
      ),
      child: Text(
        [
          if (avg != null) 'Avg score $avg',
          if (strong != null) 'Strong: $strong',
          if (weak != null) 'Focus: $weak',
        ].join(' · '),
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: ShootIQTheme.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          height: 1.35,
        ),
      ),
    );
  }
}

class _SuggestionWrap extends StatelessWidget {
  const _SuggestionWrap({
    required this.suggestions,
    required this.onSelected,
  });

  final List<String> suggestions;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final suggestion in suggestions)
          _ChipButton(
            label: suggestion,
            onTap: () => onSelected(suggestion),
          ),
      ],
    );
  }
}

class _ChipButton extends StatefulWidget {
  const _ChipButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<_ChipButton> createState() => _ChipButtonState();
}

class _ChipButtonState extends State<_ChipButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1,
        duration: const Duration(milliseconds: 110),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: ShootIQTheme.cardBackground,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: ShootIQTheme.basketballOrange.withValues(alpha: 0.32),
            ),
          ),
          child: Text(
            widget.label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: ShootIQTheme.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatList extends StatelessWidget {
  const _ChatList({
    required this.messages,
    required this.scrollController,
    required this.isTyping,
    required this.isStreaming,
    required this.streamingText,
    required this.typingController,
    required this.onQuickAction,
  });

  final List<AiCoachMessage> messages;
  final ScrollController scrollController;
  final bool isTyping;
  final bool isStreaming;
  final String streamingText;
  final AnimationController typingController;
  final void Function(String action, AiCoachMessage message) onQuickAction;

  @override
  Widget build(BuildContext context) {
    final extra = (isTyping ? 1 : 0) + (isStreaming ? 1 : 0);

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      itemCount: messages.length + extra,
      itemBuilder: (context, index) {
        if (isTyping && index == messages.length) {
          return Padding(
            padding: const EdgeInsets.only(top: 10),
            child: _TypingBubble(controller: typingController),
          );
        }
        if (isStreaming &&
            index == messages.length + (isTyping ? 1 : 0)) {
          return Padding(
            padding: const EdgeInsets.only(top: 10),
            child: _AssistantBubble(
              text: streamingText.isEmpty ? '…' : streamingText,
              showActions: false,
              onQuickAction: null,
            ),
          );
        }

        final message = messages[index];
        final showActions = message.isAssistant &&
            index == messages.length - 1 &&
            !isTyping &&
            !isStreaming;

        return Padding(
          padding: EdgeInsets.only(top: index == 0 ? 0 : 12),
          child: message.isUser
              ? _UserBubble(text: message.text)
              : _AssistantBubble(
                  text: message.text,
                  showActions: showActions,
                  onQuickAction: showActions
                      ? (action) => onQuickAction(action, message)
                      : null,
                ),
        );
      },
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: const BoxDecoration(
            color: ShootIQTheme.basketballOrange,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(6),
            ),
          ),
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              height: 1.4,
            ),
          ),
        ),
      ),
    );
  }
}

class _AssistantBubble extends StatelessWidget {
  const _AssistantBubble({
    required this.text,
    required this.showActions,
    required this.onQuickAction,
  });

  final String text;
  final bool showActions;
  final ValueChanged<String>? onQuickAction;

  static const _actions = [
    'Ask Follow-up',
    'Practice Today',
    'Generate Drills',
    'Open Drills',
    'Create Workout',
    'Analyze My Shot',
    'Save Conversation',
  ];

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.88,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: ShootIQTheme.cardBackground,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(6),
                  bottomRight: Radius.circular(18),
                ),
                border: Border.all(
                  color: ShootIQTheme.cardBorder,
                ),
              ),
              child: MarkdownBody(
                data: text,
                selectable: true,
                styleSheet: MarkdownStyleSheet(
                  p: const TextStyle(
                    color: ShootIQTheme.textPrimary,
                    fontSize: 15,
                    height: 1.45,
                  ),
                  h3: const TextStyle(
                    color: ShootIQTheme.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    height: 1.3,
                  ),
                  strong: const TextStyle(
                    color: ShootIQTheme.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                  em: const TextStyle(
                    color: ShootIQTheme.textSecondary,
                    fontStyle: FontStyle.italic,
                  ),
                  listBullet: const TextStyle(
                    color: ShootIQTheme.basketballOrange,
                    fontSize: 15,
                  ),
                  a: const TextStyle(
                    color: ShootIQTheme.basketballOrange,
                  ),
                ),
              ),
            ),
            if (showActions && onQuickAction != null) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final action in _actions)
                    _ActionChip(
                      label: action,
                      onTap: () => onQuickAction!(action),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ShootIQTheme.surfaceElevated,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: ShootIQTheme.cardBorder),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: ShootIQTheme.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble({required this.controller});

  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: ShootIQTheme.cardBackground,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(6),
            bottomRight: Radius.circular(18),
          ),
          border: Border.all(color: ShootIQTheme.cardBorder),
        ),
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (index) {
                final offset = (controller.value + (index * 0.2)) % 1.0;
                final bounce = (1 - (offset - 0.5).abs() * 2).clamp(0.0, 1.0);
                return Padding(
                  padding: EdgeInsets.only(right: index == 2 ? 0 : 6),
                  child: Transform.translate(
                    offset: Offset(0, -4 * bounce),
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: ShootIQTheme.basketballOrange.withValues(
                          alpha: 0.45 + (0.55 * bounce),
                        ),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.onSend,
    required this.enabled,
    required this.bottomPadding,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;
  final bool enabled;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 10, 16, bottomPadding),
      decoration: BoxDecoration(
        color: ShootIQTheme.cardBackground,
        border: Border(
          top: BorderSide(color: ShootIQTheme.cardBorder),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              enabled: enabled,
              minLines: 1,
              maxLines: 4,
              style: const TextStyle(
                color: ShootIQTheme.textPrimary,
                fontSize: 15,
              ),
              cursorColor: ShootIQTheme.basketballOrange,
              textInputAction: TextInputAction.send,
              onSubmitted: enabled ? (_) => onSend() : null,
              inputFormatters: [
                LengthLimitingTextInputFormatter(1200),
              ],
              decoration: InputDecoration(
                hintText: 'Ask anything about your shot...',
                hintStyle: const TextStyle(color: ShootIQTheme.textSecondary),
                filled: true,
                fillColor: ShootIQTheme.surfaceElevated,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide(
                    color: ShootIQTheme.cardBorder,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: const BorderSide(
                    color: ShootIQTheme.basketballOrange,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: enabled ? onSend : null,
            child: AnimatedOpacity(
              opacity: enabled ? 1 : 0.45,
              duration: const Duration(milliseconds: 150),
              child: Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: ShootIQTheme.basketballOrange,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.send_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
