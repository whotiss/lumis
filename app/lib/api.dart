import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'config.dart';
import 'models.dart';

/// Everything that can go wrong with a request, in a form the screens can show.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.code, this.detail});

  /// No connection, or the server could not be reached in time.
  ApiException.offline()
      : message = "Lumis can't reach its server. Check your internet connection and try again.",
        statusCode = null,
        code = 'offline',
        detail = null;

  final String message;
  final int? statusCode;
  final String? code; // e.g. consent_required, consent_outdated, no_skin, offline
  final Map<String, dynamic>? detail;

  bool get isOffline => code == 'offline';

  @override
  String toString() => 'ApiException($statusCode, $code): $message';
}

class Api {
  Api({http.Client? client, this.baseUrl = apiBaseUrl}) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;
  String? token;

  /// Called when the server says the login is no longer valid (expired or deleted account).
  void Function()? onUnauthorized;

  Map<String, String> get _auth => token == null ? {} : {'Authorization': 'Bearer $token'};

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  Future<http.Response> _send(Future<http.Response> Function() request, {Duration timeout = requestTimeout}) async {
    final http.Response r;
    try {
      r = await request().timeout(timeout);
    } on SocketException {
      throw ApiException.offline();
    } on TimeoutException {
      throw ApiException.offline();
    } on http.ClientException {
      throw ApiException.offline();
    }
    if (r.statusCode >= 200 && r.statusCode < 300) return r;
    throw _error(r);
  }

  ApiException _error(http.Response r) {
    if (r.statusCode == 401 && token != null) onUnauthorized?.call();
    Object? detail;
    try {
      detail = (jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>)['detail'];
    } catch (_) {
      detail = null;
    }
    if (detail is Map<String, dynamic>) {
      final message = (detail['message'] ?? detail['headline'] ?? 'Something went wrong.') as String;
      return ApiException(message, statusCode: r.statusCode, code: detail['code'] as String?, detail: detail);
    }
    if (detail is String) return ApiException(detail, statusCode: r.statusCode);
    if (detail is List) {
      return ApiException('Please check the details you entered.', statusCode: r.statusCode, code: 'invalid');
    }
    if (r.statusCode >= 500) {
      return ApiException('The Lumis server had a problem. Please try again in a moment.', statusCode: r.statusCode);
    }
    return ApiException('Something went wrong (${r.statusCode}).', statusCode: r.statusCode);
  }

  dynamic _json(http.Response r) => jsonDecode(utf8.decode(r.bodyBytes));

  Future<dynamic> _get(String path, [Map<String, String>? query]) async =>
      _json(await _send(() => _client.get(_uri(path, query), headers: _auth)));

  Future<dynamic> _postJson(String path, Object body) async => _json(await _send(() => _client.post(_uri(path),
      headers: {..._auth, 'Content-Type': 'application/json'}, body: jsonEncode(body))));

  // ------------------------------------------------------------------ accounts and consent

  Future<ConsentDocument> consent(String lang) async =>
      ConsentDocument.fromJson(await _get('/consent', {'lang': lang}) as Map<String, dynamic>);

  Future<String> register({
    required String email,
    required String password,
    required String consentVersion,
    required bool confirmAdult,
    required bool consentStorage,
    required bool consentLocation,
  }) async {
    final j = await _postJson('/auth/register', {
      'email': email,
      'password': password,
      'accept_consent_version': consentVersion,
      'confirm_adult': confirmAdult,
      'consent_storage': consentStorage,
      'consent_location': consentLocation,
    }) as Map<String, dynamic>;
    return j['access_token'] as String;
  }

  Future<String> login(String email, String password) async {
    final r = await _send(() => _client.post(_uri('/auth/login'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'username': email, 'password': password}));
    return (_json(r) as Map<String, dynamic>)['access_token'] as String;
  }

  Future<AppUser> me() async => AppUser.fromJson(await _get('/me') as Map<String, dynamic>);

  Future<AppUser> acceptConsent(String version) async =>
      AppUser.fromJson(await _postJson('/me/consent/accept', {'version': version, 'confirm_adult': true})
          as Map<String, dynamic>);

  Future<AppUser> updateConsent({bool? storage, bool? location}) async {
    final r = await _send(() => _client.patch(_uri('/me/consent'),
        headers: {..._auth, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'consent_storage': ?storage,
          'consent_location': ?location,
        })));
    return AppUser.fromJson(_json(r) as Map<String, dynamic>);
  }

  Future<void> deleteAccount() async {
    await _send(() => _client.delete(_uri('/me'), headers: _auth));
  }

  // ------------------------------------------------------------------ screenings

  /// Sends the photo. Throws ApiException with code no_skin / poor_photo / nothing_detected when the photo
  /// check stops it (use [photoProblem] to read the message), consent_required when consent is outdated.
  ///
  /// [onUpload] reports how much of the photo has been sent (0 to 1), so the analyzing screen can show real
  /// progress for that step. The rest of the wait (the model and Claude) has no progress to report.
  Future<Screening> createScreening(Uint8List jpeg, SymptomDetails details,
      {void Function(double sent)? onUpload}) async {
    final form = http.MultipartRequest('POST', _uri('/screenings'))
      ..headers.addAll(_auth)
      ..files.add(http.MultipartFile.fromBytes('image', jpeg,
          filename: 'photo.jpg', contentType: MediaType('image', 'jpeg')));
    if (details.duration != null) form.fields['duration'] = details.duration!;
    if (details.itchy != null) form.fields['itchy'] = '${details.itchy}';
    if (details.changing != null) form.fields['changing'] = '${details.changing}';
    final r = await _send(() async {
      final total = form.contentLength;
      final body = form.finalize();
      final request = http.StreamedRequest('POST', form.url)
        ..headers.addAll(form.headers)
        ..contentLength = total;
      var sent = 0;
      body.listen(
        (chunk) {
          sent += chunk.length;
          if (total > 0) onUpload?.call(sent / total);
          request.sink.add(chunk);
        },
        onDone: request.sink.close,
        onError: request.sink.addError,
        cancelOnError: true,
      );
      return http.Response.fromStream(await _client.send(request));
    }, timeout: screeningTimeout);
    onUpload?.call(1);
    return Screening.fromJson(_json(r) as Map<String, dynamic>);
  }

  static PhotoProblem? photoProblem(ApiException e) {
    final d = e.detail;
    final isPhotoCheck = e.statusCode == 422 && d != null && d['code'] is String && d['headline'] is String &&
        d['advice'] is String;
    return isPhotoCheck ? PhotoProblem.fromJson(d!) : null;
  }

  Future<List<Screening>> history() async =>
      [for (final s in await _get('/screenings') as List) Screening.fromJson(s as Map<String, dynamic>)];

  Future<Uint8List> screeningImage(int id) async =>
      (await _send(() => _client.get(_uri('/screenings/$id/image'), headers: _auth))).bodyBytes;

  Future<void> deleteScreening(int id) async {
    await _send(() => _client.delete(_uri('/screenings/$id'), headers: _auth));
  }

  // ------------------------------------------------------------------ reference information

  /// The model in use and its test results (for the "How reliable Lumis is" part of the doctor's PDF).
  Future<ModelInfo> modelInfo() async => ModelInfo.fromJson(await _get('/model') as Map<String, dynamic>);

  Future<List<Condition>> conditions() async =>
      [for (final c in await _get('/conditions') as List) Condition.fromJson(c as Map<String, dynamic>)];

  Future<ClinicList> clinics() async => ClinicList.fromJson(await _get('/clinics') as Map<String, dynamic>);

  /// The location goes in the request body (never in the address), is used to sort and is not stored.
  Future<ClinicList> nearbyClinics(double lat, double lon, {int limit = 20}) async =>
      ClinicList.fromJson(await _postJson('/clinics/nearby', {'lat': lat, 'lon': lon, 'limit': limit})
          as Map<String, dynamic>);
}
