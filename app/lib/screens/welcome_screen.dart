import 'package:flutter/material.dart';

import '../sparkle.dart';
import '../theme.dart';
import '../widgets.dart';
import 'consent_screen.dart';
import 'login_screen.dart';

/// Onboarding: what Lumis is and is not, before anything else (CP1 section 3.4.2).
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight - 52),
              child: IntrinsicHeight(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const SizedBox(height: 40),
                  Expanded(
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Sparkle(size: 170, animate: true),
                      const SizedBox(height: 26),
                      Semantics(
                        header: true,
                        label: 'Lumis',
                        child: ExcludeSemantics(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 12), // balances the letter spacing after the S
                            child: Text('LUMIS',
                                style: TextStyle(
                                    fontFamily: headingFont,
                                    fontWeight: FontWeight.w300,
                                    fontSize: 40,
                                    letterSpacing: 12,
                                    color: p.ink)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 310),
                        child: Text(
                          'A skin screening aid for Malaysia. Take a photo, see which of five common conditions it '
                          'looks most like, and find a dermatologist near you.',
                          textAlign: TextAlign.center,
                          style: t.bodyLarge?.copyWith(color: p.body),
                        ),
                      ),
                      const SizedBox(height: 14),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 300),
                        child: Text(
                          'Lumis is a screening aid, not a diagnosis. It can be wrong. Only a doctor can diagnose a '
                          'skin condition.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w300, height: 1.5, color: p.faint),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 28),
                  LumisButton(
                    label: 'Get started',
                    onPressed: () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => const ConsentScreen(mode: ConsentMode.register))),
                  ),
                  const SizedBox(height: 10),
                  LumisButton.secondary(
                    label: 'I already have an account',
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen())),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
