import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'models.dart';

/// "Share with a doctor": one A4 page a person can show at a clinic. It says plainly that Lumis is not a
/// diagnosis and how often its results were right in testing, so a doctor can weigh it.
Future<Uint8List> buildDoctorReport({required Screening s, Uint8List? photo, ModelInfo? model}) async {
  Future<pw.Font> font(String name) async => pw.Font.ttf(await rootBundle.load('assets/fonts/$name.ttf'));
  final light = await font('Inter-300');
  final regular = await font('Inter-400');
  final semibold = await font('Inter-600');
  final heading = await font('Jost-300');
  final wordmark = await font('Jost-400');

  const ink = PdfColor.fromInt(0xFF1C1B3A);
  const muted = PdfColor.fromInt(0xFF5E5C7A);
  const faint = PdfColor.fromInt(0xFF6E6C88);
  const nebula = PdfColor.fromInt(0xFFF3F1FF);
  const nebulaText = PdfColor.fromInt(0xFF2E2C5A);
  const line = PdfColor.fromInt(0xFFE6E1D6);

  pw.Widget label(String text) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 4),
        child: pw.Text(text.toUpperCase(),
            style: pw.TextStyle(font: regular, fontSize: 7.5, letterSpacing: 1.4, color: faint)),
      );
  pw.Widget body(String text, {pw.Font? f, PdfColor color = ink}) =>
      pw.Text(text, style: pw.TextStyle(font: f ?? regular, fontSize: 9.5, lineSpacing: 2.5, color: color));
  String yn(bool? v) => v == null ? 'Not answered' : (v ? 'Yes' : 'No');
  String pct(double? v) => v == null ? '-' : '${(v * 100).round()}%';

  final (name, otherNames) = s.nameParts;
  final band = switch (s.band) { 'high' => 'High', 'moderate' => 'Low', _ => 'Inconclusive' };
  final d = s.symptomDetails;
  final sameModel = model != null && model.modelVersion == s.modelVersion;
  final classes = sameModel && model.classes.isNotEmpty
      ? model.classes.join(', ')
      : 'acne, eczema, psoriasis, scabies and tinea';
  final reliability = <String>[
    if (sameModel && model.phoneTest != null)
      'On ${model.phoneTest!.n} test photos taken with phones (SCIN dataset), results marked High were correct '
          '${pct(model.phoneTest!.accuracyHigh)} of the time and results marked Low ${pct(model.phoneTest!.accuracyLow)}.',
    if (sameModel && model.clinicalTest != null)
      'On ${model.clinicalTest!.n} clinical photos (DermNet), overall accuracy was ${pct(model.clinicalTest!.accuracy)}.',
    if (!sameModel) 'Test results for this model version were not available when this summary was made.',
    'Accuracy can be lower on photos unlike the ones it was tested on.',
  ].join(' ');

  const star = '<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">'
      '<path d="M50 4 C52 40 60 48 96 50 C60 52 52 60 50 96 C48 60 40 52 4 50 C40 48 48 40 50 4 Z" fill="#4C46D1"/></svg>';

  final doc = pw.Document(title: 'Lumis skin screening summary', author: 'Lumis', creator: 'Lumis app');
  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(44, 40, 44, 32),
    theme: pw.ThemeData.withFont(base: regular, bold: semibold),
    build: (context) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 12),
        decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: ink, width: 0.8))),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          pw.SizedBox(width: 22, height: 22, child: pw.SvgImage(svg: star)),
          pw.SizedBox(width: 9),
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('LUMIS', style: pw.TextStyle(font: wordmark, fontSize: 11, letterSpacing: 3.3, color: ink)),
              pw.Text('Skin screening summary', style: pw.TextStyle(font: heading, fontSize: 17, color: ink)),
            ]),
          ),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            body('Screened ${DateFormat('d MMM yyyy, h:mm a').format(s.createdAt)}', color: muted),
            body('Reference LUM-${s.id.toString().padLeft(6, '0')}', color: muted),
          ]),
        ]),
      ),
      pw.SizedBox(height: 14),
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: pw.BoxDecoration(color: nebula, borderRadius: pw.BorderRadius.circular(4)),
        child: body(
            'This is not a diagnosis. Lumis is a screening aid made as a student project. It has not been '
            'clinically validated. Please use your own assessment.',
            color: nebulaText),
      ),
      pw.SizedBox(height: 16),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        if (photo != null) ...[
          pw.Container(
            width: 150,
            height: 150,
            decoration: pw.BoxDecoration(border: pw.Border.all(color: line), borderRadius: pw.BorderRadius.circular(4)),
            child: pw.ClipRRect(
              horizontalRadius: 4,
              verticalRadius: 4,
              child: pw.Image(pw.MemoryImage(photo), fit: pw.BoxFit.cover),
            ),
          ),
          pw.SizedBox(width: 18),
        ],
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            label('Lumis result'),
            pw.Text(s.conditionName == null ? 'Inconclusive' : name,
                style: pw.TextStyle(font: heading, fontSize: 18, color: ink)),
            if (otherNames != null) body(otherNames, color: muted),
            pw.SizedBox(height: 6),
            pw.RichText(
              text: pw.TextSpan(style: pw.TextStyle(font: regular, fontSize: 9.5, color: ink), children: [
                const pw.TextSpan(text: 'Confidence: '),
                pw.TextSpan(text: band, style: pw.TextStyle(font: semibold)),
                pw.TextSpan(text: '. ${s.headline}'),
              ]),
            ),
            pw.SizedBox(height: 8),
            body('Lumis only chooses between $classes. It cannot say that a photo shows none of these.',
                f: light, color: muted),
          ]),
        ),
      ]),
      pw.SizedBox(height: 18),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            label("Patient's answers"),
            for (final (q, a) in [
              ('How long', SymptomDetails.durationLabels[d?.duration] ?? 'Not answered'),
              ('Itchy', yn(d?.itchy)),
              ('Changed or spread recently', yn(d?.changing)),
            ])
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 2),
                child: pw.Row(children: [
                  pw.SizedBox(width: 120, child: body(q, color: muted)),
                  pw.Expanded(child: body(a)),
                ]),
              ),
          ]),
        ),
        pw.SizedBox(width: 20),
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            label('Photo description (written by AI)'),
            body(s.explanation?.inYourPhoto ?? 'No description for this screening.',
                color: s.explanation?.inYourPhoto == null ? muted : ink),
          ]),
        ),
      ]),
      pw.SizedBox(height: 18),
      label('How reliable Lumis is'),
      body(reliability),
      if (s.explanation != null) ...[
        pw.SizedBox(height: 18),
        label('What the app told the patient'),
        body(s.advice),
      ],
      pw.Spacer(),
      pw.Container(
        padding: const pw.EdgeInsets.only(top: 8),
        decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: line, width: 0.6))),
        child: pw.Row(children: [
          pw.Expanded(
            child: pw.Text(
                'Model ${s.modelVersion} · Photo description by Claude (Anthropic) · Made with the Lumis app, '
                'a final-year project at Sunway University',
                style: pw.TextStyle(font: light, fontSize: 7, color: faint)),
          ),
          pw.Text('Page 1 of 1', style: pw.TextStyle(font: light, fontSize: 7, color: faint)),
        ]),
      ),
    ]),
  ));
  return doc.save();
}
