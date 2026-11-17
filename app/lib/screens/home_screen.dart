import 'package:flutter/material.dart';

import 'capture_screen.dart';
import 'clinics_screen.dart';
import 'conditions_screen.dart';
import 'history_screen.dart';
import 'settings_screen.dart';

/// One prominent action (start a screening) and quiet access to everything else (CP1 section 3.4.2).
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    void open(Widget screen) => Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

    Widget tile(IconData icon, String title, String subtitle, Widget screen) => Card(
          color: Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16), side: BorderSide(color: scheme.outlineVariant)),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            leading: Icon(icon, color: scheme.primary),
            title: Text(title),
            subtitle: Text(subtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => open(screen),
          ),
        );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lumis'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => open(const SettingsScreen()),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(20)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Check a skin concern', style: t.titleLarge?.copyWith(color: scheme.onPrimaryContainer)),
              const SizedBox(height: 6),
              Text('Take a close-up photo. Lumis tells you which condition it looks most like and how sure it is.',
                  style: TextStyle(color: scheme.onPrimaryContainer)),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Start a screening'),
                onPressed: () => open(const CaptureScreen()),
              ),
            ]),
          ),
          const SizedBox(height: 20),
          tile(Icons.history, 'Your screenings', 'Past results, and delete them', const HistoryScreen()),
          const SizedBox(height: 10),
          tile(Icons.local_hospital_outlined, 'Find a dermatologist', 'Hospitals and clinics in the Klang Valley',
              const ClinicsScreen()),
          const SizedBox(height: 10),
          tile(Icons.menu_book_outlined, 'About the conditions', 'The five conditions Lumis screens for',
              const ConditionsScreen()),
          const SizedBox(height: 24),
          Text('Lumis is a screening aid, not a medical diagnosis. If you are worried, or it is painful, spreading '
              'fast or you feel unwell, see a doctor.',
              style: t.bodySmall, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
