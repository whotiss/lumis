import 'package:flutter/material.dart';

import 'consent_screen.dart';
import 'login_screen.dart';

/// Onboarding: what Lumis is and is not, before anything else (CP1 section 3.4.2).
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    Widget point(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: scheme.primary),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: t.bodyLarge)),
          ]),
        );
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
          children: [
            Icon(Icons.spa_outlined, size: 56, color: scheme.primary),
            const SizedBox(height: 16),
            Text('Lumis', style: t.displaySmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('A skin screening aid for Malaysia', style: t.titleMedium),
            const SizedBox(height: 32),
            point(Icons.photo_camera_outlined,
                'Take a photo of a skin concern. Lumis suggests which of five common conditions it looks most like: '
                'acne, eczema, psoriasis, scabies or a fungal skin infection.'),
            point(Icons.lightbulb_outline, 'You get a plain explanation and how sure Lumis is.'),
            point(Icons.local_hospital_outlined, 'Lumis shows dermatologists near you in the Klang Valley.'),
            point(Icons.health_and_safety_outlined,
                'Lumis is a screening aid, not a diagnosis. It can be wrong. Only a doctor can diagnose a skin condition.'),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const ConsentScreen(mode: ConsentMode.register))),
              child: const Text('Get started'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen())),
              child: const Text('I already have an account'),
            ),
          ],
        ),
      ),
    );
  }
}
