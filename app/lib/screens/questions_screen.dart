import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models.dart';
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

  Widget _yesNo(String question, bool? value, ValueChanged<bool?> onChanged) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(question, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      Wrap(spacing: 8, children: [
        for (final (label, v) in [('Yes', true), ('No', false), ('Not sure', null)])
          ChoiceChip(label: Text(label), selected: value == v, onSelected: (_) => onChanged(v)),
      ]),
      const SizedBox(height: 20),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('A few questions'),
        actions: [TextButton(onPressed: () => _go(const SymptomDetails()), child: const Text('Skip'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Optional. Your answers are saved with the result, so you or a doctor can see them later.'),
          const SizedBox(height: 24),
          Text('How long have you had it?', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final e in SymptomDetails.durationLabels.entries)
              ChoiceChip(
                label: Text(e.value),
                selected: _duration == e.key,
                onSelected: (on) => setState(() => _duration = on ? e.key : null),
              ),
          ]),
          const SizedBox(height: 20),
          _yesNo('Is it itchy?', _itchy, (v) => setState(() => _itchy = v)),
          _yesNo('Has it changed or spread recently?', _changing, (v) => setState(() => _changing = v)),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () => _go(SymptomDetails(duration: _duration, itchy: _itchy, changing: _changing)),
            child: const Text('Check my photo'),
          ),
        ],
      ),
    );
  }
}
