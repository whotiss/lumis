import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../auth_state.dart';
import '../config.dart';
import '../widgets.dart';
import 'consent_screen.dart';

/// Account, consent choices and deletion in one place (FR10, NFR4).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteAccount() async {
    final ok = await confirm(context,
        title: 'Delete your account?',
        body: 'Your account, every screening and every stored photo are deleted for good. '
            'This also withdraws your consent. It cannot be undone.',
        action: 'Delete everything');
    if (!ok || !mounted) return;
    final auth = context.read<AuthState>();
    final navigator = Navigator.of(context);
    await _run(() async {
      await auth.deleteAccount();
      navigator.popUntil((r) => r.isFirst);
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final user = auth.user;
    if (user == null) return const Scaffold(body: SizedBox.shrink());
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            ListTile(leading: const Icon(Icons.person_outline), title: const Text('Account'), subtitle: Text(user.email)),
            const Divider(),
            SwitchListTile(
              secondary: const Icon(Icons.photo_library_outlined),
              title: const Text('Keep my photos'),
              subtitle: const Text('See your photos in your history. Off: photos are analyzed and not kept.'),
              value: user.consentStorage,
              onChanged: (v) => _run(() => auth.updateConsent(storage: v)),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.my_location_outlined),
              title: const Text('Use my location for clinics'),
              subtitle: const Text('Only to sort clinics by distance. Never stored.'),
              value: user.consentLocation,
              onChanged: (v) => _run(() => auth.updateConsent(location: v)),
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Read the consent text'),
              subtitle: Text('You agreed to version ${user.consentVersion ?? '-'}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const ConsentScreen(mode: ConsentMode.view))),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Log out'),
              onTap: () {
                auth.logout();
                Navigator.of(context).popUntil((r) => r.isFirst);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_forever_outlined, color: Theme.of(context).colorScheme.error),
              title: Text('Delete my account', style: TextStyle(color: Theme.of(context).colorScheme.error)),
              subtitle: const Text('Deletes your account, screenings and photos'),
              onTap: _deleteAccount,
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Lumis is a final-year student project at Sunway University and a screening aid, not a medical '
                'device. To ask for a copy of your data, see the contact in the consent text.\nServer: $apiBaseUrl',
                style: t.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
