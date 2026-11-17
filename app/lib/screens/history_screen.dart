import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../models.dart';
import '../sparkle.dart';
import '../theme.dart';
import '../widgets.dart';
import 'result_screen.dart';

/// Past screenings, newest first; open one to review it, or delete it (FR7, FR10).
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Screening>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await context.read<Api>().history();
      if (mounted) {
        setState(() {
          _items = items;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _delete(Screening s) async {
    await context.read<Api>().deleteScreening(s.id);
    if (mounted) setState(() => _items?.removeWhere((x) => x.id == s.id));
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      appBar: lumisAppBar(context, title: 'History'),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : items == null
              ? const Center(child: Sparkle(size: 56, animate: true))
              : items.isEmpty
                  ? const ErrorView(message: 'No screenings yet. Your results will appear here.')
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
                        itemCount: items.length,
                        separatorBuilder: (context, i) => const SizedBox(height: 10),
                        itemBuilder: (context, i) => _HistoryTile(
                          s: items[i],
                          onOpen: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ResultScreen(
                                  screening: items[i], fromHistory: true, onDelete: () => _delete(items[i])),
                            ),
                          ),
                        ),
                      ),
                    ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.s, required this.onOpen});
  final Screening s;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Panel(
      padding: const EdgeInsets.all(16),
      onTap: onOpen,
      child: Row(children: [
        Sparkle(size: 30, style: sparkleFor(s.band)),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.nameParts.$1, style: Theme.of(context).textTheme.titleMedium),
            Text('${DateFormat('d MMM yyyy').format(s.createdAt)} · ${s.bandLabel}',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w300, color: p.muted)),
          ]),
        ),
        if (s.imageAvailable) ...[
          Icon(Icons.photo_outlined, size: 18, color: p.starOutline),
          const SizedBox(width: 6),
        ],
        Icon(Icons.chevron_right_rounded, color: p.starOutline),
      ]),
    );
  }
}
