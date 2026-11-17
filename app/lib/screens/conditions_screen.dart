import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../models.dart';
import '../sparkle.dart';
import '../theme.dart';
import '../widgets.dart';

/// Reference information on the five conditions Lumis screens for (FR8).
class ConditionsScreen extends StatefulWidget {
  const ConditionsScreen({super.key});

  @override
  State<ConditionsScreen> createState() => _ConditionsScreenState();
}

class _ConditionsScreenState extends State<ConditionsScreen> {
  List<Condition>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await context.read<Api>().conditions();
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

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      appBar: lumisAppBar(context, title: 'About the conditions'),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : items == null
              ? const Center(child: Sparkle(size: 56, animate: true))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
                  children: [
                    for (final c in items) ...[
                      Panel(
                        padding: const EdgeInsets.all(16),
                        onTap: () => Navigator.push(
                            context, MaterialPageRoute(builder: (_) => ConditionDetailScreen(condition: c))),
                        child: Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(c.name, style: Theme.of(context).textTheme.titleMedium),
                              Text(c.category,
                                  style: TextStyle(
                                      fontSize: 13, fontWeight: FontWeight.w300, color: context.palette.muted)),
                            ]),
                          ),
                          Icon(Icons.chevron_right_rounded, color: context.palette.starOutline),
                        ]),
                      ),
                      const SizedBox(height: 10),
                    ],
                    const SizedBox(height: 8),
                    Text('Lumis only screens for these five conditions. Many other skin conditions look similar, '
                        'so see a doctor if you are unsure.',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
    );
  }
}

class ConditionDetailScreen extends StatelessWidget {
  const ConditionDetailScreen({super.key, required this.condition});
  final Condition condition;

  @override
  Widget build(BuildContext context) {
    final c = condition;
    const gap = SizedBox(height: 14);
    return Scaffold(
      appBar: lumisAppBar(context, title: c.name),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(c.category, style: Theme.of(context).textTheme.titleSmall),
          gap,
          if (c.about != null) ...[
            InfoCard(title: 'What it is', icon: Icons.menu_book_outlined, child: Text(c.about!)),
            gap,
          ],
          InfoCard(title: 'Common signs', icon: Icons.checklist_outlined, child: Text(c.typicalPresentation)),
          gap,
          InfoCard(title: 'What you can do', icon: Icons.healing_outlined, child: Text(c.generalGuidance)),
          gap,
          if (c.urgencyDefault == 'see_doctor') ...[
            const DisclaimerBanner('This condition needs a doctor to confirm and treat it.'),
            gap,
          ],
          Text('General information, not medical advice for you.', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
