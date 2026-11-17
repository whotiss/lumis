// Tests that need no server and no phone: the API's JSON is read correctly, and the result screen shows what the
// server sent, including the screening-aid statement. Run with: flutter test
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lumis/api.dart';
import 'package:lumis/models.dart';
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
      child: MaterialApp(theme: lumisTheme(), home: child),
    );

void main() {
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
      await tester.pumpWidget(wrap(ResultScreen(screening: sample())));
      expect(find.textContaining('This looks most like'), findsOneWidget);
      expect(find.text('High confidence'), findsOneWidget);
      expect(find.textContaining('screening aid, not a medical diagnosis'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('In your photo'), 200);
      expect(find.text('In your photo'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Common signs'), 200);
      expect(find.text('Common signs'), findsOneWidget);
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
      expect(find.text('In your photo'), findsNothing);
      expect(find.text('Find a dermatologist near you'), findsOneWidget);
    });

    testWidgets('confidence is shown as a band, never a percentage', (tester) async {
      await tester.pumpWidget(wrap(const Scaffold(body: BandIndicator(band: 'moderate', label: 'Low confidence'))));
      expect(find.text('Low confidence'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
    });
  });
}
