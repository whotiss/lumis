/// Data from the Lumis API. The shapes match backend/app/schemas.py.
library;

/// "Fungal skin infection (tinea or ringworm)" → ("Fungal skin infection", "Tinea or ringworm").
(String, String?) splitConditionName(String name) {
  final m = RegExp(r'^(.*?)\s*\((.+)\)\s*$').firstMatch(name);
  if (m == null) return (name, null);
  final other = m.group(2)!;
  return (m.group(1)!, other[0].toUpperCase() + other.substring(1));
}

DateTime _date(Object? v) => DateTime.parse(v as String).toLocal();
String? _str(Object? v) => v as String?;

class ConsentItem {
  ConsentItem({required this.id, required this.required, required this.label});
  final String id;
  final bool required;
  final String label;

  factory ConsentItem.fromJson(Map<String, dynamic> j) =>
      ConsentItem(id: j['id'] as String, required: j['required'] as bool, label: j['label'] as String);
}

class ConsentSection {
  ConsentSection({required this.heading, required this.body});
  final String heading;
  final String body;

  factory ConsentSection.fromJson(Map<String, dynamic> j) =>
      ConsentSection(heading: j['heading'] as String, body: j['body'] as String);
}

class ConsentDocument {
  ConsentDocument({
    required this.version,
    required this.language,
    required this.title,
    required this.sections,
    required this.items,
  });
  final String version;
  final String language;
  final String title;
  final List<ConsentSection> sections;
  final List<ConsentItem> items;

  factory ConsentDocument.fromJson(Map<String, dynamic> j) => ConsentDocument(
        version: j['version'] as String,
        language: j['language'] as String,
        title: j['title'] as String,
        sections: [for (final s in j['sections'] as List) ConsentSection.fromJson(s as Map<String, dynamic>)],
        items: [for (final i in j['items'] as List) ConsentItem.fromJson(i as Map<String, dynamic>)],
      );
}

class AppUser {
  AppUser({
    required this.id,
    required this.email,
    required this.consentStorage,
    required this.consentLocation,
    required this.consentVersion,
    required this.consentCurrent,
  });
  final int id;
  final String email;
  final bool consentStorage;
  final bool consentLocation;
  final String? consentVersion;
  final bool consentCurrent;

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: j['id'] as int,
        email: j['email'] as String,
        consentStorage: j['consent_storage'] as bool,
        consentLocation: j['consent_location'] as bool,
        consentVersion: _str(j['consent_version']),
        consentCurrent: j['consent_current'] as bool,
      );
}

/// Optional answers before a screening (FR2). Stored with the result; they do not change it.
class SymptomDetails {
  const SymptomDetails({this.duration, this.itchy, this.changing});
  final String? duration; // under_1_week | 1_to_4_weeks | over_1_month
  final bool? itchy;
  final bool? changing;

  bool get isEmpty => duration == null && itchy == null && changing == null;

  factory SymptomDetails.fromJson(Map<String, dynamic> j) => SymptomDetails(
        duration: _str(j['duration']),
        itchy: j['itchy'] as bool?,
        changing: j['changing'] as bool?,
      );

  static const durationLabels = {
    'under_1_week': 'Less than a week',
    '1_to_4_weeks': '1 to 4 weeks',
    'over_1_month': 'More than a month',
  };
}

class Explanation {
  Explanation({
    required this.whatItIs,
    required this.commonSigns,
    required this.inYourPhoto,
    required this.whatToDo,
    required this.photoBased,
  });
  final String whatItIs;
  final String commonSigns;
  final String? inYourPhoto;
  final String whatToDo;
  final bool photoBased;

  factory Explanation.fromJson(Map<String, dynamic> j) => Explanation(
        whatItIs: j['what_it_is'] as String,
        commonSigns: j['common_signs'] as String,
        inYourPhoto: _str(j['in_your_photo']),
        whatToDo: j['what_to_do'] as String,
        photoBased: j['photo_based'] as bool,
      );
}

class Screening {
  Screening({
    required this.id,
    required this.createdAt,
    required this.band,
    required this.bandLabel,
    required this.conditionId,
    required this.conditionName,
    required this.headline,
    required this.advice,
    required this.recommendedAction,
    required this.showClinics,
    required this.disclaimer,
    required this.symptomDetails,
    required this.imageAvailable,
    required this.modelVersion,
    required this.explanation,
  });
  final int id;
  final DateTime createdAt;
  final String band; // high | moderate | refer
  final String bandLabel;
  final String? conditionId; // null when inconclusive: no condition is named
  final String? conditionName;
  final String headline;
  final String advice;
  final String recommendedAction; // see_doctor | monitor
  final bool showClinics;
  final String disclaimer;
  final SymptomDetails? symptomDetails;
  final bool imageAvailable;
  final String modelVersion;
  final Explanation? explanation;

  /// "Fungal skin infection (tinea or ringworm)" → ("Fungal skin infection", "Tinea or ringworm"), so the
  /// result can show the plain name large and the other names under it.
  (String, String?) get nameParts => splitConditionName(conditionName ?? 'Inconclusive');

  factory Screening.fromJson(Map<String, dynamic> j) {
    final condition = j['condition'] as Map<String, dynamic>?;
    final details = j['symptom_details'] as Map<String, dynamic>?;
    final explanation = j['explanation'] as Map<String, dynamic>?;
    return Screening(
      id: j['id'] as int,
      createdAt: _date(j['created_at']),
      band: j['band'] as String,
      bandLabel: j['band_label'] as String,
      conditionId: condition?['id'] as String?,
      conditionName: condition?['name'] as String?,
      headline: j['headline'] as String,
      advice: j['advice'] as String,
      recommendedAction: j['recommended_action'] as String,
      showClinics: j['show_clinics'] as bool,
      disclaimer: j['disclaimer'] as String,
      symptomDetails: details == null ? null : SymptomDetails.fromJson(details),
      imageAvailable: j['image_available'] as bool,
      modelVersion: j['model_version'] as String,
      explanation: explanation == null ? null : Explanation.fromJson(explanation),
    );
  }
}

/// A photo the server would not judge (no skin, too unclear, unlike anything Lumis knows, or skin that looks
/// normal). The server sends the wording, so new kinds need no app update.
class PhotoProblem {
  PhotoProblem({required this.code, required this.headline, required this.advice, required this.disclaimer});
  final String code; // no_skin | poor_photo | nothing_detected | no_visible_change
  final String headline;
  final String advice;
  final String disclaimer;

  factory PhotoProblem.fromJson(Map<String, dynamic> j) => PhotoProblem(
        code: j['code'] as String,
        headline: j['headline'] as String,
        advice: j['advice'] as String,
        disclaimer: (j['disclaimer'] as String?) ?? '',
      );
}

class Condition {
  Condition({
    required this.id,
    required this.name,
    required this.category,
    required this.about,
    required this.typicalPresentation,
    required this.generalGuidance,
    required this.urgencyDefault,
  });
  final String id;
  final String name;
  final String category;
  final String? about;
  final String typicalPresentation;
  final String generalGuidance;
  final String urgencyDefault;

  factory Condition.fromJson(Map<String, dynamic> j) => Condition(
        id: j['id'] as String,
        name: j['name'] as String,
        category: j['category'] as String,
        about: _str(j['about']),
        typicalPresentation: j['typical_presentation'] as String,
        generalGuidance: j['general_guidance'] as String,
        urgencyDefault: j['urgency_default'] as String,
      );
}

class Clinic {
  Clinic({
    required this.id,
    required this.name,
    required this.type,
    required this.city,
    required this.address,
    required this.phone,
    required this.website,
    required this.note,
    required this.childrenOnly,
    required this.access,
    required this.lat,
    required this.lon,
    required this.distanceKm,
  });
  final String id;
  final String name;
  final String type;
  final String city;
  final String address;
  final String? phone;
  final String? website;
  final String? note;
  final bool childrenOnly;
  final String access;
  final double? lat;
  final double? lon;
  final double? distanceKm;

  static const typeLabels = {
    'government_hospital': 'Government hospital',
    'university_hospital': 'University hospital',
    'private_hospital': 'Private hospital',
    'specialist_clinic': "Dermatologist's clinic",
  };

  String get typeLabel => typeLabels[type] ?? type;

  factory Clinic.fromJson(Map<String, dynamic> j) => Clinic(
        id: j['id'] as String,
        name: j['name'] as String,
        type: j['type'] as String,
        city: j['city'] as String,
        address: j['address'] as String,
        phone: _str(j['phone']),
        website: _str(j['website']),
        note: _str(j['note']),
        childrenOnly: (j['children_only'] as bool?) ?? false,
        access: j['access'] as String,
        lat: (j['lat'] as num?)?.toDouble(),
        lon: (j['lon'] as num?)?.toDouble(),
        distanceKm: (j['distance_km'] as num?)?.toDouble(),
      );
}

class ClinicList {
  ClinicList({required this.clinics, required this.checked, required this.attribution, required this.outsideCoverage});
  final List<Clinic> clinics;
  final String checked;
  final String attribution;
  final bool outsideCoverage;

  factory ClinicList.fromJson(Map<String, dynamic> j) {
    final d = j['directory'] as Map<String, dynamic>;
    return ClinicList(
      clinics: [for (final c in j['clinics'] as List) Clinic.fromJson(c as Map<String, dynamic>)],
      checked: d['checked'] as String,
      attribution: d['attribution'] as String,
      outsideCoverage: (j['outside_coverage'] as bool?) ?? false,
    );
  }
}

/// One test of the model on held-out photos, as stored with the model (backend models/*.json).
class TestResult {
  TestResult({required this.n, required this.accuracy, this.accuracyHigh, this.accuracyLow});
  final int n;
  final double accuracy;
  final double? accuracyHigh; // how often "High confidence" results were right
  final double? accuracyLow; // how often "Low confidence" (moderate band) results were right

  static TestResult? tryParse(Object? j) {
    if (j is! Map<String, dynamic> || j['n'] is! num || j['accuracy'] is! num) return null;
    return TestResult(
      n: (j['n'] as num).toInt(),
      accuracy: (j['accuracy'] as num).toDouble(),
      accuracyHigh: (j['accuracy_high'] as num?)?.toDouble(),
      accuracyLow: (j['accuracy_moderate'] as num?)?.toDouble(),
    );
  }
}

class ModelInfo {
  ModelInfo({required this.modelVersion, required this.classes, this.phoneTest, this.clinicalTest});
  final String modelVersion;
  final List<String> classes;
  final TestResult? phoneTest; // SCIN: photos people took themselves
  final TestResult? clinicalTest; // DermNet: clinical photos

  factory ModelInfo.fromJson(Map<String, dynamic> j) {
    final t = j['test_results'];
    final tests = t is Map<String, dynamic> ? t : const <String, dynamic>{};
    return ModelInfo(
      modelVersion: j['model_version'] as String,
      classes: [for (final c in (j['classes'] as List? ?? const [])) c as String],
      phoneTest: TestResult.tryParse(tests['scin_test']),
      clinicalTest: TestResult.tryParse(tests['dermnet_test']),
    );
  }
}
