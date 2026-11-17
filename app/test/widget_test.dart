// Tests that need no server and no phone: the API's JSON is read correctly, and the result screen shows what the
// server sent, including the screening-aid statement. Run with: flutter test
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumis/api.dart';
import 'package:lumis/models.dart';
import 'package:lumis/report_pdf.dart';
import 'package:lumis/screens/result_screen.dart';
import 'package:lumis/theme.dart';
import 'package:lumis/widgets.dart';
import 'package:provider/provider.dart';

// Shaped exactly like a response from POST /screenings on the live server (2026-11-17).
const screeningJson = '''
{"id": 7, "created_at": "2026-11-17T12:03:44.386248Z", "band": "high", "band_label": "High confidence",
 "condition": {"id": "tinea", "name": "Fungal skin infection (tinea or ringworm)"}, "confidence": 0.81,
 "headline": "This looks most like Fungal skin infection (tinea or ringworm).",
 "advice": "If it does not improve, spreads, or worries you, please see a doctor.",
 "recommended_action": "monitor", "show_clinics": false,
 "disclaimer": "Lumis is a screening aid, not a medical diagnosis. Only a doctor can diagnose a skin condition.",
 "symptom_details": {"duration": "1_to_4_weeks", "itchy": true}, "image_available": false,
 "model_version": "lumis-medsiglip-v3",
 "explanation": {"what_it_is": "A fungal skin infection is caused by a fungus.",
   "common_signs": "A red, ring-shaped patch with a scaly edge.",
   "in_your_photo": "In your photo, a round red patch is on the leg. These are common signs of a fungal skin infection (tinea).",
   "what_to_do": "Keep the area clean and dry.", "photo_based": true}}
''';

Screening sample({String band = 'high', bool explanation = true}) {
  final j = jsonDecode(screeningJson) as Map<String, dynamic>;
  j['band'] = band;
  if (band == 'refer') j['condition'] = null;
  if (!explanation) j['explanation'] = null;
  return Screening.fromJson(j);
}

Widget wrap(Widget child, {Api? api}) => Provider<Api>.value(
      value: api ?? Api(client: MockClient((_) async => http.Response('', 500))),
      child: MaterialApp(theme: lumisTheme(Brightness.light), home: child),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('reading the API', () {
    test('a screening with its explanation', () {
      final s = sample();
      expect(s.conditionId, 'tinea');
      expect(s.explanation!.photoBased, isTrue);
      expect(s.symptomDetails!.itchy, isTrue);
      expect(s.symptomDetails!.changing, isNull);
      expect(s.createdAt.isUtc, isFalse); // shown in the phone's time zone
    });

    test('an inconclusive screening names no condition', () {
      final s = sample(band: 'refer', explanation: false);
      expect(s.conditionId, isNull);
      expect(s.explanation, isNull);
    });

    test('a clinic list from POST /clinics/nearby', () {
      final list = ClinicList.fromJson(jsonDecode('''
        {"directory": {"version": "2026-11-17", "checked": "2026-11-17", "coverage": "Klang Valley",
          "inclusion": "x", "sources": {}, "attribution": "Map data © OpenStreetMap contributors"},
         "outside_coverage": false,
         "clinics": [{"id": "sunway-mc", "name": "Sunway Medical Centre", "type": "private_hospital",
           "city": "Bandar Sunway", "address": "5, Jalan Lagoon Selatan", "phone": "+60 3-7491 9191",
           "website": null, "note": null, "children_only": false, "access": "Call to book.",
           "lat": 3.0661113, "lon": 101.6085546, "location_precision": "building", "location_source": "x",
           "dermatologist_source": [], "distance_km": 0.6}]}''') as Map<String, dynamic>);
      expect(list.clinics.single.typeLabel, 'Private hospital');
      expect(list.clinics.single.distanceKm, 0.6);
      expect(list.attribution, contains('OpenStreetMap'));
    });
  });

  group('errors from the server', () {
    test('a photo the check stopped becomes a PhotoProblem', () async {
      final api = Api(client: MockClient((_) async => http.Response(
          jsonEncode({'detail': {'code': 'no_skin', 'headline': 'No skin detected.', 'advice': 'Retake it.',
                                  'disclaimer': 'Lumis is a screening aid.'}}), 422)));
      try {
        await api.createScreening(utf8.encode('jpeg'), const SymptomDetails());
        fail('should throw');
      } on ApiException catch (e) {
        expect(Api.photoProblem(e)!.headline, 'No skin detected.');
      }
    });

    test('a new kind of photo check needs no app update', () async {
      final api = Api(client: MockClient((_) async => http.Response(
          jsonEncode({'detail': {'code': 'no_visible_change', 'headline': "Lumis couldn't see a skin problem.",
                                  'advice': 'This does not mean your skin is healthy.', 'disclaimer': 'x'}}), 422)));
      try {
        await api.createScreening(utf8.encode('jpeg'), const SymptomDetails());
        fail('should throw');
      } on ApiException catch (e) {
        expect(Api.photoProblem(e)!.code, 'no_visible_change');
      }
    });

    test('a lost connection is reported as offline', () async {
      final api = Api(client: MockClient((_) async => throw http.ClientException('no network')));
      expect(() => api.conditions(), throwsA(isA<ApiException>().having((e) => e.isOffline, 'offline', true)));
    });

    test('an expired login logs the person out', () async {
      var loggedOut = false;
      final api = Api(client: MockClient((_) async => http.Response('{"detail": "Please log in again."}', 401)))
        ..token = 'old'
        ..onUnauthorized = () => loggedOut = true;
      await expectLater(api.me(), throwsA(isA<ApiException>()));
      expect(loggedOut, isTrue);
    });

    test('the location is sent in the body, not the address', () async {
      late http.Request sent;
      final api = Api(client: MockClient((r) async {
        sent = r;
        return http.Response(jsonEncode({
          'directory': {'checked': 'x', 'attribution': 'y'},
          'outside_coverage': false,
          'clinics': [],
        }), 200);
      }));
      await api.nearbyClinics(3.0672, 101.6037);
      expect(sent.method, 'POST');
      expect(sent.url.query, isEmpty);
      expect(jsonDecode(sent.body)['lat'], 3.0672);
    });
  });

  group('result screen', () {
    testWidgets('shows the condition, the band, the explanation and the screening-aid statement', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(wrap(ResultScreen(screening: sample())));
      expect(find.textContaining('This looks most like'), findsOneWidget);
      expect(find.text('High'), findsOneWidget); // the bright step of the confidence scale
      expect(find.bySemanticsLabel('Confidence: High confidence'), findsOneWidget);
      expect(find.textContaining('screening aid, not a medical diagnosis'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('IN YOUR PHOTO'), 200);
      expect(find.text('IN YOUR PHOTO'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('COMMON SIGNS'), 200);
      expect(find.text('COMMON SIGNS'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('an inconclusive result shows no explanation and offers clinics', (tester) async {
      final j = jsonDecode(screeningJson) as Map<String, dynamic>
        ..['band'] = 'refer'
        ..['band_label'] = 'Inconclusive'
        ..['condition'] = null
        ..['explanation'] = null
        ..['show_clinics'] = true
        ..['headline'] = "Lumis can't tell what this is from this photo.";
      await tester.pumpWidget(wrap(ResultScreen(screening: Screening.fromJson(j))));
      expect(find.text('IN YOUR PHOTO'), findsNothing);
      expect(find.text('Inconclusive'), findsWidgets); // named as inconclusive, no condition
      expect(find.text('Find a dermatologist near you'), findsOneWidget);
    });

    testWidgets('confidence is shown as a three-step scale, never a percentage', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(wrap(const Scaffold(body: ConfidenceScale(band: 'moderate', label: 'Low confidence'))));
      expect(find.text('Inconclusive'), findsOneWidget);
      expect(find.text('Low'), findsOneWidget);
      expect(find.text('High'), findsOneWidget);
      expect(find.text('Moderate'), findsNothing); // the moderate band is labeled low (decided 2026-11-15)
      expect(find.bySemanticsLabel('Confidence: Low confidence'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
      expect(ConfidenceScale.stepFor('moderate'), 1);
      expect(ConfidenceScale.stepFor('refer'), 0);
      semantics.dispose();
    });

    test('condition names split into a plain name and other names', () {
      expect(splitConditionName('Fungal skin infection (tinea or ringworm)'),
          ('Fungal skin infection', 'Tinea or ringworm'));
      expect(splitConditionName('Acne'), ('Acne', null));
    });
  });

  group('sending a photo', () {
    test('reports upload progress up to the whole photo', () async {
      final progress = <double>[];
      final api = Api(client: MockClient((r) async => http.Response(screeningJson, 200)));
      final s = await api.createScreening(Uint8List(50000), const SymptomDetails(), onUpload: progress.add);
      expect(s.id, 7);
      expect(progress, isNotEmpty);
      expect(progress.last, 1.0);
      for (var i = 1; i < progress.length; i++) {
        expect(progress[i], greaterThanOrEqualTo(progress[i - 1]));
      }
    });
  });

  group('doctor PDF', () {
    test('model test results are read from GET /model', () {
      final m = ModelInfo.fromJson(jsonDecode('''
        {"model_version": "lumis-medsiglip-v3", "classes": ["acne", "eczema", "psoriasis", "scabies", "tinea"],
         "bands": {}, "test_results": {
           "scin_test": {"n": 121, "accuracy": 0.694, "accuracy_high": 0.878, "accuracy_moderate": 0.308},
           "dermnet_test": {"n": 972, "accuracy": 0.704}}}''') as Map<String, dynamic>);
      expect(m.phoneTest!.n, 121);
      expect(m.phoneTest!.accuracyLow, 0.308);
      expect(m.clinicalTest!.accuracyHigh, isNull);
    });

    test('builds a one-page PDF without a photo or test results', () async {
      final bytes = await buildDoctorReport(s: sample());
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });
  });
}
