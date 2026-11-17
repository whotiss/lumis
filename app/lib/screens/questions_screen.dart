import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'processing_screen.dart';

/// Three optional questions (FR2). Skippable: they are saved with the result for you or a doctor to see,
/// and they do not change what Lumis says about the photo.
class QuestionsScreen extends StatefulWidget {
  const QuestionsScreen({super.key, required this.photo});
  final Uint8List photo;

  @override
  State<QuestionsScreen> createState() => _QuestionsScreenState();
}

class _QuestionsScreenState extends State<QuestionsScreen> {
  String? _duration;
  bool? _itchy;
  bool? _changing;

  void _go(SymptomDetails details) => Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => ProcessingScreen(photo: widget.photo, details: details)),
        (r) => r.isFirst, // back from the result goes home, not to the camera
      );

  Widget _choices<T>(String question, List<(String, T)> options, T? value, ValueChanged<T?> onChanged) {
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(question, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (label, v) in options)
            ChoiceChip(
              label: Text(label),
              selected: value == v && value != null,
              onSelected: (on) => onChanged(on ? v : null),
            ),
        ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      appBar: lumisAppBar(context, title: 'A few questions', actions: [
        TextButton(onPressed: () => _go(const SymptomDetails()), child: const Text('Skip')),
      ]),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          Text('Optional. Your answers are saved with the result, so you or a doctor can see them later. '
              'They do not change what Lumis says about the photo.',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w300, height: 1.5, color: p.muted)),
          const SizedBox(height: 18),
          _choices<String>('How long have you had it?',
              [for (final e in SymptomDetails.durationLabels.entries) (e.value, e.key)], _duration,
              (v) => setState(() => _duration = v)),
          const SizedBox(height: 10),
          _choices<bool>('Is it itchy?', const [('Yes', true), ('No', false)], _itchy,
              (v) => setState(() => _itchy = v)),
          const SizedBox(height: 10),
          _choices<bool>('Has it changed or spread recently?', const [('Yes', true), ('No', false)], _changing,
              (v) => setState(() => _changing = v)),
          const SizedBox(height: 22),
          LumisButton(
            label: 'Check my photo',
            onPressed: () => _go(SymptomDetails(duration: _duration, itchy: _itchy, changing: _changing)),
          ),
        ],
      ),
    );
  }
}
