import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../auth_state.dart';
import '../models.dart';
import '../sparkle.dart';
import '../widgets.dart';
import 'register_screen.dart';

enum ConsentMode {
  register, // before creating an account
  update, // the text changed since the person agreed: agree again before the next screening
  view, // read only, from Settings
}

/// The consent text from the server, in English or Bahasa Malaysia (PDPA: both must be offered).
/// Required boxes start unticked; nothing is implied by using the app (NFR4).
class ConsentScreen extends StatefulWidget {
  const ConsentScreen({super.key, required this.mode});
  final ConsentMode mode;

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  String _lang = 'en';
  ConsentDocument? _doc;
  String? _error;
  final Map<String, bool> _ticked = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthState>().user;
    if (widget.mode == ConsentMode.update && user != null) {
      _ticked['storage'] = user.consentStorage; // keep the person's current choices
      _ticked['location'] = user.consentLocation;
    }
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final doc = await context.read<Api>().consent(_lang);
      if (mounted) setState(() => _doc = doc);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  bool get _canContinue =>
      _doc != null && _doc!.items.where((i) => i.required).every((i) => _ticked[i.id] == true);

  Future<void> _continue() async {
    final doc = _doc!;
    if (widget.mode == ConsentMode.register) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RegisterScreen(
            consentVersion: doc.version,
            consentStorage: _ticked['storage'] ?? false,
            consentLocation: _ticked['location'] ?? false,
          ),
        ),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<AuthState>().acceptConsent(doc.version,
          storage: _ticked['storage'] ?? false, location: _ticked['location'] ?? false);
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    final t = Theme.of(context).textTheme;
    final view = widget.mode == ConsentMode.view;
    return Scaffold(
      appBar: lumisAppBar(
        context,
        title: widget.mode == ConsentMode.update ? 'Updated terms' : 'Your consent',
        actions: [
          if (widget.mode == ConsentMode.update)
            TextButton(onPressed: () => context.read<AuthState>().logout(), child: const Text('Log out')),
        ],
      ),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : doc == null
              ? const Center(child: Sparkle(size: 56, animate: true))
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'en', label: Text('English')),
                        ButtonSegment(value: 'ms', label: Text('Bahasa Malaysia')),
                      ],
                      selected: {_lang},
                      onSelectionChanged: (s) {
                        setState(() {
                          _lang = s.first;
                          _doc = null;
                        });
                        _load();
                      },
                    ),
                    const SizedBox(height: 20),
                    if (widget.mode == ConsentMode.update) ...[
                      const DisclaimerBanner('The consent text has changed since you last agreed. Please read it '
                          'and agree again before your next screening. Your history stays available either way.'),
                      const SizedBox(height: 16),
                    ],
                    Text(doc.title, style: t.headlineSmall),
                    const SizedBox(height: 12),
                    for (final s in doc.sections) ...[
                      Text(s.heading, style: t.titleMedium),
                      const SizedBox(height: 4),
                      Text(s.body, style: t.bodyMedium?.copyWith(height: 1.45)),
                      const SizedBox(height: 16),
                    ],
                    Text('Version ${doc.version}', style: t.bodySmall),
                    if (!view) ...[
                      const Divider(height: 32),
                      for (final item in doc.items)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          value: _ticked[item.id] ?? false,
                          onChanged: (v) => setState(() => _ticked[item.id] = v ?? false),
                          title: Text(item.label),
                          subtitle: Text(item.required ? 'Required' : 'Optional, you can change this later'),
                        ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _canContinue && !_busy ? _continue : null,
                        child: _busy
                            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                            : Text(widget.mode == ConsentMode.register ? 'Continue' : 'I agree'),
                      ),
                    ],
                  ],
                ),
    );
  }
}
