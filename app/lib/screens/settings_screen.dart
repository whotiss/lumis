import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../app_settings.dart';
import '../auth_state.dart';
import '../config.dart';
import '../theme.dart';
import '../widgets.dart';
import 'consent_screen.dart';

/// Appearance, consent choices, account and deletion in one place (FR10, NFR4).
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
    final settings = context.watch<AppSettings>();
    final user = auth.user;
    if (user == null) return const Scaffold(body: SizedBox.shrink());
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    const gap = SizedBox(height: 22);
    return Scaffold(
      appBar: lumisAppBar(context, title: 'Settings'),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
          children: [
            const SectionLabel('Appearance'),
            const SizedBox(height: 10),
            SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                ButtonSegment(value: ThemeMode.system, label: Text('Match phone')),
              ],
              selected: {settings.themeMode},
              onSelectionChanged: (s) => settings.setThemeMode(s.first),
            ),
            gap,
            const SectionLabel('Privacy'),
            const SizedBox(height: 10),
            _Group(children: [
              _SwitchRow(
                title: 'Keep my photos',
                subtitle: 'See your photos in your history. Off: photos are analyzed and not kept.',
                value: user.consentStorage,
                onChanged: (v) => _run(() => auth.updateConsent(storage: v)),
              ),
              _SwitchRow(
                title: 'Use my location for clinics',
                subtitle: 'Only to sort clinics by distance. Never stored.',
                value: user.consentLocation,
                onChanged: (v) => _run(() => auth.updateConsent(location: v)),
              ),
              _LinkRow(
                title: 'Read the consent text',
                subtitle: 'You agreed to version ${user.consentVersion ?? '-'}',
                onTap: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const ConsentScreen(mode: ConsentMode.view))),
              ),
            ]),
            gap,
            const SectionLabel('Account'),
            const SizedBox(height: 10),
            _Group(children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Signed in as', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w300, color: p.muted)),
                  Text(user.email, style: t.titleSmall),
                ]),
              ),
              _LinkRow(
                title: 'Log out',
                onTap: () {
                  auth.logout();
                  Navigator.of(context).popUntil((r) => r.isFirst);
                },
              ),
              _LinkRow(title: 'Delete my account', danger: true, onTap: _deleteAccount),
            ]),
            gap,
            Text(
              'Lumis is a final-year student project at Sunway University and a screening aid, not a medical '
              'device. To ask for a copy of your data, see the contact in the consent text.\nServer: $apiBaseUrl',
              style: t.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Rows in one glossy card, separated by hairlines.
class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Panel(
      padding: EdgeInsets.zero,
      child: Column(children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) Divider(height: 1, color: p.divider),
          children[i],
        ],
      ]),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({required this.title, required this.subtitle, required this.value, required this.onChanged});
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(fontSize: 13, height: 1.4, fontWeight: FontWeight.w300, color: p.muted)),
            ]),
          ),
          const SizedBox(width: 8),
          Switch(value: value, onChanged: onChanged),
        ]),
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.title, this.subtitle, required this.onTap, this.danger = false});
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w400, color: danger ? p.danger : p.ink)),
              if (subtitle != null)
                Text(subtitle!, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w300, color: p.muted)),
            ]),
          ),
          if (!danger) Icon(Icons.chevron_right_rounded, color: p.starOutline),
        ]),
      ),
    );
  }
}
