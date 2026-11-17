import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../models.dart';
import '../widgets.dart';
import 'clinics_screen.dart';

/// The result: condition, banded confidence with a sentence, the explanation, and the screening-aid statement
/// shown alongside rather than buried (FR3, FR4, FR5, FR9). Every sentence comes from the server (NFR8).
class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key, required this.screening, this.fromHistory = false, this.onDelete});
  final Screening screening;
  final bool fromHistory;
  final Future<void> Function()? onDelete;

  @override
  Widget build(BuildContext context) {
    final s = screening;
    final t = Theme.of(context).textTheme;
    final e = s.explanation;
    const gap = SizedBox(height: 14);
    return Scaffold(
      appBar: AppBar(
        title: Text(fromHistory ? DateFormat('d MMM yyyy, h:mm a').format(s.createdAt) : 'Your result'),
        actions: [
          if (onDelete != null)
            IconButton(
              tooltip: 'Delete this screening',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final ok = await confirm(context,
                    title: 'Delete this screening?',
                    body: 'The result and its photo are deleted for good.',
                    action: 'Delete');
                if (!ok) return;
                try {
                  await onDelete!();
                  if (context.mounted) Navigator.pop(context);
                } on ApiException catch (e) {
                  if (context.mounted) showMessage(context, e.message);
                }
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (fromHistory && s.imageAvailable) ...[_StoredPhoto(id: s.id), gap],
          BandIndicator(band: s.band, label: s.bandLabel),
          const SizedBox(height: 10),
          Text(s.headline, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
          gap,
          DisclaimerBanner(s.disclaimer),
          gap,
          InfoCard(
            title: 'What Lumis suggests',
            icon: s.recommendedAction == 'see_doctor' ? Icons.local_hospital_outlined : Icons.visibility_outlined,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(s.advice, style: t.bodyLarge),
              if (s.showClinics) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.place_outlined),
                  label: const Text('Find a dermatologist near you'),
                  onPressed: () =>
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const ClinicsScreen())),
                ),
              ],
            ]),
          ),
          if (e != null) ...[
            if (e.inYourPhoto != null) ...[
              gap,
              InfoCard(title: 'In your photo', icon: Icons.center_focus_strong_outlined, child: Text(e.inYourPhoto!)),
            ],
            if (e.whatItIs.isNotEmpty) ...[
              gap,
              InfoCard(
                  title: 'About ${s.conditionName ?? 'this condition'}',
                  icon: Icons.menu_book_outlined,
                  child: Text(e.whatItIs)),
            ],
            gap,
            InfoCard(title: 'Common signs', icon: Icons.checklist_outlined, child: Text(e.commonSigns)),
            gap,
            InfoCard(title: 'What you can do', icon: Icons.healing_outlined, child: Text(e.whatToDo)),
          ],
          if (s.symptomDetails != null && !s.symptomDetails!.isEmpty) ...[
            gap,
            InfoCard(title: 'Your answers', icon: Icons.question_answer_outlined, child: _Answers(s.symptomDetails!)),
          ],
          if (!s.showClinics) ...[
            gap,
            OutlinedButton.icon(
              icon: const Icon(Icons.place_outlined),
              label: const Text('Find a dermatologist'),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ClinicsScreen())),
            ),
          ],
          const SizedBox(height: 20),
          Text(
            'Screened ${DateFormat('d MMM yyyy, h:mm a').format(s.createdAt)} with model ${s.modelVersion}.'
            '${e != null && e.inYourPhoto != null ? ' "In your photo" was written by Claude (Anthropic) from your photo.' : ''}',
            style: t.bodySmall,
          ),
          if (!fromHistory) ...[
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: () => Navigator.pop(context), child: const Text('Done')),
          ],
        ],
      ),
    );
  }
}

class _Answers extends StatelessWidget {
  const _Answers(this.d);
  final SymptomDetails d;

  @override
  Widget build(BuildContext context) {
    String yn(bool? v) => v == null ? 'Not answered' : (v ? 'Yes' : 'No');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('How long: ${SymptomDetails.durationLabels[d.duration] ?? 'Not answered'}'),
      Text('Itchy: ${yn(d.itchy)}'),
      Text('Changed or spread recently: ${yn(d.changing)}'),
    ]);
  }
}

/// The stored photo, loaded with the login token (only kept if the person turned on "Keep my photos").
class _StoredPhoto extends StatefulWidget {
  const _StoredPhoto({required this.id});
  final int id;

  @override
  State<_StoredPhoto> createState() => _StoredPhotoState();
}

class _StoredPhotoState extends State<_StoredPhoto> {
  late final Future<Uint8List> _photo = context.read<Api>().screeningImage(widget.id);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _photo,
      builder: (context, snap) {
        if (snap.hasData) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(aspectRatio: 1, child: Image.memory(snap.data!, fit: BoxFit.cover)),
          );
        }
        if (snap.hasError) return const Text('The photo could not be loaded.');
        return const AspectRatio(aspectRatio: 1, child: Center(child: CircularProgressIndicator()));
      },
    );
  }
}
