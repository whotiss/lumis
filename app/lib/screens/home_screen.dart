import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../app_settings.dart';
import '../models.dart';
import '../sparkle.dart';
import '../theme.dart';
import '../widgets.dart';
import 'capture_screen.dart';
import 'clinics_screen.dart';
import 'conditions_screen.dart';
import 'history_screen.dart';
import 'result_screen.dart';
import 'settings_screen.dart';

/// One prominent action (start a screening) and quiet access to everything else (CP1 section 3.4.2).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Screening? _last;

  @override
  void initState() {
    super.initState();
    _loadLast();
  }

  Future<void> _loadLast() async {
    try {
      final items = await context.read<Api>().history();
      if (mounted) setState(() => _last = items.isEmpty ? null : items.first);
    } on ApiException {
      // the card is optional: leave it out if history can't load
    }
  }

  Future<void> _open(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    _loadLast(); // a new screening, or a deleted one, changes the "last screening" card
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final brightness = Theme.of(context).brightness;
    final last = _last;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          children: [
            Row(children: [
              const LumisWordmark(),
              const Spacer(),
              SquareIconButton(
                icon: brightness == Brightness.dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                tooltip: brightness == Brightness.dark ? 'Switch to light mode' : 'Switch to dark mode',
                onPressed: () => context.read<AppSettings>().toggle(brightness),
              ),
              const SizedBox(width: 8),
              SquareIconButton(
                icon: Icons.tune_rounded,
                tooltip: 'Settings',
                onPressed: () => _open(const SettingsScreen()),
              ),
            ]),
            const SizedBox(height: 22),
            Panel(
              raised: true,
              radius: 12,
              padding: EdgeInsets.zero,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(children: [
                  const Positioned(right: -10, top: -10, child: Sparkle(size: 150, animate: true)),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      const SectionLabel('Skin check'),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.only(right: 110),
                        child: Text('Check a skin concern', style: t.headlineLarge),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Take a close-up photo. Lumis tells you which of five conditions it looks most like, and how '
                        'sure it is.',
                        style: t.bodyMedium?.copyWith(color: p.body),
                      ),
                      const SizedBox(height: 20),
                      LumisButton(
                        label: 'Start a screening',
                        icon: Icons.photo_camera_outlined,
                        onPressed: () => _open(const CaptureScreen()),
                      ),
                    ]),
                  ),
                ]),
              ),
            ),
            if (last != null) ...[
              const SizedBox(height: 22),
              const SectionLabel('Last screening'),
              const SizedBox(height: 10),
              Panel(
                padding: const EdgeInsets.all(16),
                onTap: () => _open(ResultScreen(screening: last, fromHistory: true)),
                child: Row(children: [
                  Sparkle(size: 30, style: sparkleFor(last.band)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(last.nameParts.$1, style: t.titleMedium),
                      Text('${DateFormat('d MMM').format(last.createdAt)} · ${last.bandLabel}',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w300, color: p.muted)),
                    ]),
                  ),
                  Icon(Icons.chevron_right_rounded, color: p.starOutline),
                ]),
              ),
            ],
            const SizedBox(height: 14),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: _Tile(
                  icon: Icons.place_outlined,
                  title: 'Dermatologists',
                  subtitle: 'Near you, Klang Valley',
                  tone: PanelTone.nebula,
                  onTap: () => _open(const ClinicsScreen()),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Tile(
                  icon: Icons.history_rounded,
                  title: 'History',
                  subtitle: 'Your past results',
                  onTap: () => _open(const HistoryScreen()),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            Panel(
              padding: const EdgeInsets.all(16),
              onTap: () => _open(const ConditionsScreen()),
              child: Row(children: [
                Icon(Icons.menu_book_outlined, size: 20, color: p.accent),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('About the conditions', style: t.titleMedium),
                    Text('Acne, eczema, psoriasis, scabies, fungal',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w300, color: p.muted)),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 26),
            Text(
              'Lumis is a screening aid, not a medical diagnosis. If you are worried, or it is painful, spreading fast '
              'or you feel unwell, see a doctor.',
              textAlign: TextAlign.center,
              style: t.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.title, required this.subtitle, required this.onTap, this.tone});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final PanelTone? tone;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Panel(
      tone: tone ?? PanelTone.paper,
      padding: const EdgeInsets.all(16),
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 20, color: p.accent),
        const SizedBox(height: 26),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        Text(subtitle, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w300, color: p.muted)),
      ]),
    );
  }
}
