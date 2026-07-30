import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shootiq/config/theme.dart';
import 'package:shootiq/models/shot_coach_context.dart';
import 'package:shootiq/router/app_router.dart';
import 'package:shootiq/services/shot_coach_service.dart';

enum _ChatRole { user, assistant }

class _ChatMessage {
  const _ChatMessage({
    required this.id,
    required this.role,
    required this.text,
  });

  final String id;
  final _ChatRole role;
  final String text;

  bool get isUser => role == _ChatRole.user;
}

class ShotAiChatPage extends StatefulWidget {
  const ShotAiChatPage({super.key, required this.contextData});

  final ShotCoachContext contextData;

  @override
  State<ShotAiChatPage> createState() => _ShotAiChatPageState();
}

class _ShotAiChatPageState extends State<ShotAiChatPage>
    with TickerProviderStateMixin {
  static const _suggestions = [
    'Why did I lose points?',
    "What's my biggest mistake?",
    'Give me drills.',
    'Compare to my last shot.',
    'How do I shoot like Steph Curry?',
    'What should I practice today?',
  ];

  late final AnimationController _fadeController;
  late final AnimationController _typingController;
  late final Animation<double> _fadeAnimation;
  late final TextEditingController _inputController;
  late final ScrollController _scrollController;

  final List<_ChatMessage> _messages = [];
  final List<String> _priorUserQuestions = [];

  bool _isTyping = false;
  bool _showSuggestions = true;
  Timer? _replyTimer;

  @override
  void initState() {
    super.initState();
    _inputController = TextEditingController();
    _scrollController = ScrollController();

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

    _messages.add(
      _ChatMessage(
        id: 'welcome',
        role: _ChatRole.assistant,
        text: _welcomeText(widget.contextData),
      ),
    );

    _fadeController.forward();
  }

  static String _welcomeText(ShotCoachContext ctx) {
    final weak = ctx.weakestCategory;
    final score = ctx.overallScore;
    final focus = weak != null
        ? ' I already see ${weak.key} (${weak.value}) as a top focus area.'
        : '';
    return 'I have this shot loaded — overall score $score.$focus\n\n'
        'Ask anything in plain English (“Why do I fall forward?”) or tap a '
        'suggested question. I remember this conversation.';
  }

  @override
  void dispose() {
    _replyTimer?.cancel();
    _inputController.dispose();
    _scrollController.dispose();
    _fadeController.dispose();
    _typingController.dispose();
    super.dispose();
  }

  Future<void> _scrollToBottom() async {
    await Future<void>.delayed(const Duration(milliseconds: 40));
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  void _sendMessage(String rawText) {
    final text = rawText.trim();
    if (text.isEmpty || _isTyping) return;

    setState(() {
      _showSuggestions = false;
      _messages.add(
        _ChatMessage(
          id: 'u_${DateTime.now().millisecondsSinceEpoch}',
          role: _ChatRole.user,
          text: text,
        ),
      );
      _priorUserQuestions.add(text);
      _isTyping = true;
      _inputController.clear();
    });
    _scrollToBottom();

    _replyTimer?.cancel();
    _replyTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      final answer = ShotCoachService.reply(
        question: text,
        context: widget.contextData,
        priorUserQuestions: List<String>.from(_priorUserQuestions)..removeLast(),
      );
      setState(() {
        _isTyping = false;
        _messages.add(
          _ChatMessage(
            id: 'a_${DateTime.now().millisecondsSinceEpoch}',
            role: _ChatRole.assistant,
            text: answer,
          ),
        );
      });
      _scrollToBottom();
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
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: _ChatAppBar(
                  score: widget.contextData.overallScore,
                  onBack: () {
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go(AppRoutes.results);
                    }
                  },
                ),
              ),
              if (_showSuggestions) ...[
                const SizedBox(height: 14),
                SizedBox(
                  height: 42,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    scrollDirection: Axis.horizontal,
                    itemCount: _suggestions.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final suggestion = _suggestions[index];
                      return _SuggestionChip(
                        label: suggestion,
                        onTap: () => _sendMessage(suggestion),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  itemCount: _messages.length + (_isTyping ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (_isTyping && index == _messages.length) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: _TypingBubble(controller: _typingController),
                      );
                    }
                    final message = _messages[index];
                    return Padding(
                      padding: EdgeInsets.only(top: index == 0 ? 0 : 12),
                      child: _MessageBubble(message: message),
                    );
                  },
                ),
              ),
              if (!_showSuggestions)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _isTyping
                          ? null
                          : () => setState(() => _showSuggestions = true),
                      icon: const Icon(
                        Icons.lightbulb_outline_rounded,
                        size: 18,
                        color: ShootIQTheme.basketballOrange,
                      ),
                      label: const Text(
                        'Show suggested questions',
                        style: TextStyle(
                          color: ShootIQTheme.basketballOrange,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              _InputBar(
                controller: _inputController,
                enabled: !_isTyping,
                bottomPadding: bottomInset > 0 ? 8 : 12,
                onSend: () => _sendMessage(_inputController.text),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatAppBar extends StatelessWidget {
  const _ChatAppBar({
    required this.score,
    required this.onBack,
  });

  final int score;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Material(
          color: ShootIQTheme.surfaceElevated,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onBack,
            child: const SizedBox(
              width: 40,
              height: 40,
              child: Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 16,
                color: ShootIQTheme.textPrimary,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ask AI About This Shot',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: ShootIQTheme.textPrimary,
                  letterSpacing: -0.3,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Coaching grounded in your analysis',
                style: TextStyle(
                  fontSize: 12,
                  color: ShootIQTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: ShootIQTheme.basketballOrange.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: ShootIQTheme.basketballOrange.withValues(alpha: 0.4),
            ),
          ),
          child: Text(
            '$score',
            style: const TextStyle(
              color: ShootIQTheme.basketballOrange,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }
}

class _SuggestionChip extends StatefulWidget {
  const _SuggestionChip({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  State<_SuggestionChip> createState() => _SuggestionChipState();
}

class _SuggestionChipState extends State<_SuggestionChip> {
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
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: ShootIQTheme.cardBackground,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: ShootIQTheme.basketballOrange.withValues(alpha: 0.35),
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

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 10 * (1 - value)),
            child: child,
          ),
        );
      },
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.84,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: isUser
                  ? ShootIQTheme.basketballOrange
                  : ShootIQTheme.cardBackground,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(isUser ? 18 : 6),
                bottomRight: Radius.circular(isUser ? 6 : 18),
              ),
              border: isUser
                  ? null
                  : Border.all(color: ShootIQTheme.cardBorder),
            ),
            child: Text(
              message.text,
              style: TextStyle(
                fontSize: 15,
                height: 1.45,
                color: isUser ? Colors.white : ShootIQTheme.textPrimary,
              ),
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

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.onSend,
    required this.enabled,
    required this.bottomPadding,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final bool enabled;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPadding),
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
              enabled: enabled,
              style: const TextStyle(
                color: ShootIQTheme.textPrimary,
                fontSize: 15,
              ),
              cursorColor: ShootIQTheme.basketballOrange,
              textInputAction: TextInputAction.send,
              onSubmitted: enabled ? (_) => onSend() : null,
              decoration: InputDecoration(
                hintText: 'Ask about this shot...',
                hintStyle: const TextStyle(color: ShootIQTheme.textSecondary),
                filled: true,
                fillColor: ShootIQTheme.darkBackground,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(999),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(999),
                  borderSide: BorderSide(
                    color: ShootIQTheme.cardBorder,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(999),
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
              opacity: enabled ? 1 : 0.5,
              duration: const Duration(milliseconds: 150),
              child: Container(
                width: 46,
                height: 46,
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
