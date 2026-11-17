import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../models.dart';
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
      appBar: AppBar(title: const Text('Your screenings')),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : items == null
              ? const Center(child: CircularProgressIndicator())
              : items.isEmpty
                  ? const ErrorView(message: 'No screenings yet. Your results will appear here.', icon: Icons.history)
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
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
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: scheme.outlineVariant)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: BandIndicator.colorFor(s.band).withValues(alpha: 0.15),
          child: Icon(s.imageAvailable ? Icons.photo_outlined : Icons.description_outlined,
              color: BandIndicator.colorFor(s.band)),
        ),
        title: Text(s.conditionName ?? 'Inconclusive'),
        subtitle: Text('${DateFormat('d MMM yyyy').format(s.createdAt)} · ${s.bandLabel}'),
        trailing: const Icon(Icons.chevron_right),
        onTap: onOpen,
      ),
    );
  }
}
