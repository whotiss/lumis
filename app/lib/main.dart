import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'api.dart';
import 'auth_state.dart';
import 'screens/consent_screen.dart';
import 'screens/home_screen.dart';
import 'screens/welcome_screen.dart';
import 'theme.dart';
import 'widgets.dart';

void main() {
  final api = Api();
  runApp(MultiProvider(
    providers: [
      Provider<Api>.value(value: api),
      ChangeNotifierProvider(create: (_) => AuthState(api)..start()),
    ],
    child: const LumisApp(),
  ));
}

class LumisApp extends StatelessWidget {
  const LumisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lumis',
      debugShowCheckedModeBanner: false,
      theme: lumisTheme(),
      home: const AuthGate(),
    );
  }
}

/// Chooses the first screen: welcome (logged out), consent (text changed since the person agreed), or home.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    return switch (auth.status) {
      AuthStatus.starting => const Scaffold(body: Center(child: CircularProgressIndicator())),
      AuthStatus.loggedOut => const WelcomeScreen(),
      AuthStatus.needsConsent => const ConsentScreen(mode: ConsentMode.update),
      AuthStatus.ready => const HomeScreen(),
      AuthStatus.error => Scaffold(
          body: ErrorView(message: auth.errorMessage ?? 'Something went wrong.', onRetry: auth.start),
        ),
    };
  }
}
