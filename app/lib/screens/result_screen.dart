import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../models.dart';
import '../report_pdf.dart';
import '../theme.dart';
import '../widgets.dart';
import 'clinics_screen.dart';

/// The result: condition, confidence as a three-step star scale with the server's sentence, the explanation, and
/// the screening-aid statement shown alongside rather than buried (FR3, FR4, FR5, FR9). Every sentence about the
/// result comes from the server (NFR8).
class ResultScreen extends StatefulWidget {
  const ResultScreen({super.key, required this.screening, this.photo, this.fromHistory = false, this.onDelete});
  final Screening screening;

  /// The photo just taken. From history, the stored photo is loaded instead (if the person kept photos).
  final Uint8List? photo;
  final bool fromHistory;
  final Future<void> Function()? onDelete;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  late final Future<Uint8List?> _photo;
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    _photo = widget.photo != null
        ? Future.value(widget.photo)
        : widget.screening.imageAvailable
            ? _loadStored()
            : Future.value(null);
  }

  Future<Uint8List?> _loadStored() async {
    try {
      return await context.read<Api>().screeningImage(widget.screening.id);
    } on ApiException {
      return null; // the result still shows, just without the photo
    }
  }

  Future<void> _share() async {
    setState(() => _sharing = true);
    final api = context.read<Api>();
    try {
      ModelInfo? model;
      try {
        model = await api.modelInfo();
      } on ApiException {
        model = null; // the PDF says the test results were not available
      }
      final bytes = await buildDoctorReport(s: widget.screening, photo: await _photo, model: model);
      await Printing.sharePdf(bytes: bytes, filename: 'lumis-screening-${widget.screening.id}.pdf');
    } catch (_) {
      if (mounted) showMessage(context, 'The PDF could not be made. Please try again.');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _delete() async {
    final ok = await confirm(context,
        title: 'Delete this screening?', body: 'The result and its photo are deleted for good.', action: 'Delete');
    if (!ok) return;
    try {
      await widget.onDelete!();
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message);
    }
  }

  void _clinics() => Navigator.push(context, MaterialPageRoute(builder: (_) => const ClinicsScreen()));

  @override
  Widget build(BuildContext context) {
    final s = widget.screening;
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final e = s.explanation;
    final (name, otherNames) = s.nameParts;
    const gap = SizedBox(height: 14);
    final when = DateFormat('d MMM yyyy, h:mm a').format(s.createdAt);
    return Scaffold(
      appBar: lumisAppBar(context, label: widget.fromHistory ? when : 'Your result', actions: [
        if (widget.onDelete != null)
          SquareIconButton(icon: Icons.delete_outline_rounded, tooltip: 'Delete this screening', onPressed: _delete),
      ]),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
        children: [
          Row(children: [
            FutureBuilder<Uint8List?>(
              future: _photo,
              builder: (context, snap) => snap.data == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(right: 14),
                      child: Semantics(
                        image: true,
                        label: 'Your photo',
                        child: Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: p.border),
                            image: DecorationImage(image: MemoryImage(snap.data!), fit: BoxFit.cover),
                          ),
                        ),
                      ),
                    ),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SectionLabel(s.conditionName == null ? 'Result' : 'Possible match'),
                const SizedBox(height: 4),
                Text(name, style: t.headlineSmall),
                if (otherNames != null)
                  Text(otherNames, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w300, color: p.faint)),
              ]),
            ),
          ]),
          gap,
          Panel(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const SectionLabel('How sure Lumis is'),
              const SizedBox(height: 12),
              ConfidenceScale(band: s.band, label: s.bandLabel),
              const SizedBox(height: 12),
              Text(s.headline, style: t.bodyMedium?.copyWith(color: p.nebulaText)),
            ]),
          ),
          gap,
          DisclaimerBanner(s.disclaimer),
          gap,
          Panel(
            raised: true,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const SectionLabel('What Lumis suggests'),
              const SizedBox(height: 10),
              Text(s.advice, style: t.bodyLarge),
              const SizedBox(height: 14),
              if (s.showClinics) ...[
                LumisButton(
                    label: 'Find a dermatologist near you', icon: Icons.place_outlined, onPressed: _clinics, height: 50),
                const SizedBox(height: 10),
              ],
              LumisButton.secondary(
                label: 'Share with a doctor (PDF)',
                icon: Icons.ios_share_rounded,
                busy: _sharing,
                onPressed: _share,
              ),
            ]),
          ),
          if (e?.inYourPhoto != null) ...[
            gap,
            _InYourPhoto(e!.inYourPhoto!),
          ],
          if (e != null) ...[
            gap,
            Panel(
              padding: EdgeInsets.zero,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (e.whatItIs.isNotEmpty) _Part('About', e.whatItIs),
                _Part('Common signs', e.commonSigns),
                _Part('What you can do', e.whatToDo, last: true),
              ]),
            ),
          ],
          if (s.symptomDetails != null && !s.symptomDetails!.isEmpty) ...[
            gap,
            _Answers(s.symptomDetails!),
          ],
          if (!s.showClinics) ...[
            gap,
            LumisButton.secondary(label: 'Find a dermatologist', icon: Icons.place_outlined, onPressed: _clinics),
          ],
          const SizedBox(height: 18),
          Text(
            'Screened $when with model ${s.modelVersion}.'
            '${e?.inYourPhoto != null ? ' "In your photo" was written by Claude (Anthropic) from your photo.' : ''}',
            style: t.bodySmall,
          ),
          if (!widget.fromHistory) ...[
            const SizedBox(height: 16),
            LumisButton.secondary(label: 'Done', onPressed: () => Navigator.pop(context)),
          ],
        ],
      ),
    );
  }
}

/// Claude's description. The last sentence (how well the photo fits the condition) is fixed text from the server,
/// shown in the accent color.
class _InYourPhoto extends StatelessWidget {
  const _InYourPhoto(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final cut = text.trimRight().lastIndexOf(RegExp(r'[.!?]\s+(?=\S)'));
    final (seen, fit) = cut > 0 ? (text.substring(0, cut + 1), text.substring(cut + 1).trim()) : (text, null);
    return InfoCard(
      title: 'In your photo',
      trailing: Text('Described by Claude', style: TextStyle(fontSize: 11, color: p.faint)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(seen, style: t.bodyMedium),
        if (fit != null) ...[
          const SizedBox(height: 8),
          Text(fit, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w400, color: p.accent)),
        ],
      ]),
    );
  }
}

class _Part extends StatelessWidget {
  const _Part(this.title, this.text, {this.last = false});
  final String title;
  final String text;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: p.divider))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionLabel(title),
        const SizedBox(height: 8),
        Text(text, style: Theme.of(context).textTheme.bodyMedium),
      ]),
    );
  }
}

class _Answers extends StatelessWidget {
  const _Answers(this.d);
  final SymptomDetails d;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    String yn(bool? v) => v == null ? 'Not answered' : (v ? 'Yes' : 'No');
    Widget item(String q, String a) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(q, style: TextStyle(fontSize: 12, color: p.faint)),
            const SizedBox(height: 2),
            Text(a, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: p.ink)),
          ]),
        );
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SectionLabel('Your answers'),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          item('How long', SymptomDetails.durationLabels[d.duration] ?? 'Not answered'),
          item('Itchy', yn(d.itchy)),
          item('Changing', yn(d.changing)),
        ]),
      ]),
    );
  }
}
