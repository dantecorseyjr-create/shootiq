import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shootiq/config/theme.dart';
import 'package:shootiq/models/shot_record.dart';
import 'package:shootiq/router/app_router.dart';
import 'package:shootiq/services/shot_history_service.dart';
import 'package:shootiq/widgets/empty_state.dart';
import 'package:shootiq/widgets/error_state.dart';

/// Past analyzed shots loaded from Supabase `shots` + local store.
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<ShotRecord> _shots = const [];
  bool _loading = true;
  String? _error;
  String? _deletingId;
  bool _compareMode = false;
  final List<String> _compareSelection = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _enterCompareMode({String? preselectId}) {
    setState(() {
      _compareMode = true;
      _compareSelection
        ..clear()
        ..addAll([
          if (preselectId != null) preselectId,
        ]);
    });
  }

  void _exitCompareMode() {
    setState(() {
      _compareMode = false;
      _compareSelection.clear();
    });
  }

  void _toggleCompareSelection(ShotRecord shot) {
    setState(() {
      if (_compareSelection.contains(shot.id)) {
        _compareSelection.remove(shot.id);
      } else if (_compareSelection.length < 2) {
        _compareSelection.add(shot.id);
      } else {
        // Replace second pick.
        _compareSelection[1] = shot.id;
      }
    });
  }

  void _openCompare() {
    if (_compareSelection.length != 2) return;
    final leftId = _compareSelection[0];
    final rightId = _compareSelection[1];
    _exitCompareMode();
    context.push(
      AppRoutes.sessionCompare,
      extra: {'leftId': leftId, 'rightId': rightId},
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final shots = await ShotHistoryService.getUserShots();
      if (!mounted) return;
      setState(() {
        _shots = shots;
        _loading = false;
      });
    } catch (e) {
      // ignore: avoid_print
      print('History load error: $e');
      if (!mounted) return;
      setState(() {
        _shots = const [];
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _openShot(ShotRecord shot) {
    context.push(AppRoutes.results, extra: shot.toResultsMap());
  }

  Future<void> _confirmDelete(ShotRecord shot) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: ShootIQTheme.cardBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Text(
            'Delete this shot analysis?',
            style: TextStyle(
              color: ShootIQTheme.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          content: Text(
            'This will permanently remove:\n'
            '• Original video\n'
            '• Skeleton overlay video\n'
            '• AI report\n'
            '• Scores\n'
            '• Feedback',
            style: TextStyle(
              color: ShootIQTheme.textSecondary.withValues(alpha: 0.95),
              height: 1.45,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: ShootIQTheme.errorRed,
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _deleteShot(shot);
    }
  }

  Future<void> _deleteShot(ShotRecord shot) async {
    setState(() => _deletingId = shot.id);

    try {
      await ShotHistoryService.deleteShot(shot);
      if (!mounted) return;

      setState(() {
        _shots = _shots.where((item) => item.id != shot.id).toList();
        _deletingId = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Shot deleted successfully.')),
      );
    } catch (e) {
      // ignore: avoid_print
      print('History delete error: $e');
      if (!mounted) return;
      setState(() => _deletingId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete shot. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ShootIQTheme.darkBackground,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                'Shot History',
                style: TextStyle(
                  color: ShootIQTheme.textPrimary,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _compareMode
                          ? 'Select two shots to compare '
                              '(${_compareSelection.length}/2).'
                          : 'Review past AI shot analyses.',
                      style: const TextStyle(
                        color: ShootIQTheme.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  if (_shots.length >= 2)
                    _compareMode
                        ? TextButton(
                            onPressed: _exitCompareMode,
                            child: const Text('Cancel'),
                          )
                        : TextButton.icon(
                            onPressed: _enterCompareMode,
                            icon: const Icon(
                              Icons.compare_arrows_rounded,
                              size: 18,
                            ),
                            label: const Text('Compare Shots'),
                            style: TextButton.styleFrom(
                              foregroundColor: ShootIQTheme.basketballOrange,
                            ),
                          ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                color: ShootIQTheme.basketballOrange,
                onRefresh: _load,
                child: _buildBody(),
              ),
            ),
            if (_compareMode && _compareSelection.length == 2)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _openCompare,
                      icon: const Icon(Icons.compare_arrows_rounded),
                      label: const Text(
                        'Compare Shots',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: ShootIQTheme.buttonBlue,
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: ShootIQTheme.redBorder, width: 2),
                          shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          color: ShootIQTheme.basketballOrange,
        ),
      );
    }

    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.55,
            child: ErrorState(
              type: AppErrorType.generic,
              detail: _error,
              onRetry: _load,
              onReturn: () => context.go(AppRoutes.dashboard),
              returnLabel: 'Return Home',
            ),
          ),
        ],
      );
    }

    if (_shots.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.55,
            child: EmptyState(
              icon: Icons.history_rounded,
              title: 'No shots analyzed yet',
              message:
                  'Film a basketball shot and ShootIQ will build your history here.',
              actionLabel: 'Analyze Your First Shot',
              onAction: () => context.go(AppRoutes.analyze),
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      itemCount: _shots.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final shot = _shots[index];
        final selectedIndex = _compareSelection.indexOf(shot.id);
        return _HistoryCard(
          shot: shot,
          deleting: _deletingId == shot.id,
          compareMode: _compareMode,
          compareSelectedIndex: selectedIndex >= 0 ? selectedIndex + 1 : null,
          onView: () => _openShot(shot),
          onDelete: () => _confirmDelete(shot),
          onCompare: () => _enterCompareMode(preselectId: shot.id),
          onToggleCompare: () => _toggleCompareSelection(shot),
          onRename: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Rename Shot coming soon.')),
            );
          },
        );
      },
    );
  }
}

enum _HistoryMenuAction { view, compare, rename, delete }

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.shot,
    required this.deleting,
    required this.onView,
    required this.onDelete,
    required this.onRename,
    required this.onCompare,
    required this.onToggleCompare,
    this.compareMode = false,
    this.compareSelectedIndex,
  });

  final ShotRecord shot;
  final bool deleting;
  final bool compareMode;
  final int? compareSelectedIndex;
  final VoidCallback onView;
  final VoidCallback onDelete;
  final VoidCallback onRename;
  final VoidCallback onCompare;
  final VoidCallback onToggleCompare;

  @override
  Widget build(BuildContext context) {
    final selected = compareSelectedIndex != null;

    return Opacity(
      opacity: deleting ? 0.55 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: compareMode
              ? onToggleCompare
              : null,
          borderRadius: BorderRadius.circular(18),
          child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: ShootIQTheme.cardBackground,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? ShootIQTheme.basketballOrange.withValues(alpha: 0.65)
                : ShootIQTheme.cardBorder,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (compareMode)
                  Padding(
                    padding: const EdgeInsets.only(right: 10, top: 14),
                    child: Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selected
                            ? ShootIQTheme.basketballOrange
                            : ShootIQTheme.cardBorder,
                        border: Border.all(
                          color: selected
                              ? ShootIQTheme.basketballOrange
                              : Colors.white24,
                        ),
                      ),
                      child: selected
                          ? Text(
                              '$compareSelectedIndex',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            )
                          : null,
                    ),
                  ),
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color:
                        ShootIQTheme.basketballOrange.withValues(alpha: 0.16),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${shot.overallScore}',
                    style: const TextStyle(
                      color: ShootIQTheme.basketballOrange,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shot.formattedDate,
                        style: const TextStyle(
                          color: ShootIQTheme.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        shot.shotType ?? 'Basketball Shot',
                        style: const TextStyle(
                          color: ShootIQTheme.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Score: ${shot.overallScore}',
                        style: const TextStyle(
                          color: ShootIQTheme.basketballOrangeLight,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (shot.strongestCategory != null)
                        Text(
                          'Strongest: ${shot.strongestCategory}',
                          style: TextStyle(
                            color: const Color(0xFF22C55E).withValues(alpha: 0.95),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      if (shot.needsWorkCategory != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Needs Work: ${shot.needsWorkCategory}',
                          style: TextStyle(
                            color: const Color(0xFFF59E0B).withValues(alpha: 0.95),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      if (shot.improvementSummary != null &&
                          shot.improvementSummary!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          shot.improvementSummary!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: ShootIQTheme.textSecondary.withValues(
                              alpha: 0.9,
                            ),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (deleting)
                  const Padding(
                    padding: EdgeInsets.only(top: 4, right: 4),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: ShootIQTheme.basketballOrange,
                      ),
                    ),
                  )
                else if (!compareMode)
                  PopupMenuButton<_HistoryMenuAction>(
                    tooltip: 'Shot options',
                    color: ShootIQTheme.surfaceElevated,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    icon: Icon(
                      Icons.more_vert_rounded,
                      color: Colors.white.withValues(alpha: 0.75),
                    ),
                    onSelected: (action) {
                      switch (action) {
                        case _HistoryMenuAction.view:
                          onView();
                        case _HistoryMenuAction.compare:
                          onCompare();
                        case _HistoryMenuAction.rename:
                          onRename();
                        case _HistoryMenuAction.delete:
                          onDelete();
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: _HistoryMenuAction.view,
                        child: Text('View Analysis'),
                      ),
                      PopupMenuItem(
                        value: _HistoryMenuAction.compare,
                        child: Text('Compare Shots'),
                      ),
                      PopupMenuItem(
                        value: _HistoryMenuAction.rename,
                        child: Text('Rename Shot'),
                      ),
                      PopupMenuItem(
                        value: _HistoryMenuAction.delete,
                        child: Text(
                          'Delete Shot',
                          style: TextStyle(color: ShootIQTheme.errorRed),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            if (!compareMode) ...[
              const SizedBox(height: 14),
              SizedBox(
                height: 44,
                child: OutlinedButton(
                  onPressed: deleting ? null : onView,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ShootIQTheme.textPrimary,
                    side: BorderSide(
                      color:
                          ShootIQTheme.basketballOrange.withValues(alpha: 0.5),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: const Text('View Analysis'),
                ),
              ),
            ],
          ],
        ),
          ),
        ),
      ),
    );
  }
}
