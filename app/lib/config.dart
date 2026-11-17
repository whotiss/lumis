/// Where the Lumis backend runs. Override for a local server with:
///   flutter run --dart-define=API_URL=http://10.0.2.2:8000
/// (10.0.2.2 is the computer running the Android emulator.)
const String apiBaseUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'https://lumis-api-5wamisk7nq-as.a.run.app',
);

/// A screening can wait for a cold start (the server loads the model, up to about a minute).
const Duration screeningTimeout = Duration(seconds: 90);
const Duration requestTimeout = Duration(seconds: 30);

/// After this long, the processing screen explains that the server may be starting up.
const Duration slowNotice = Duration(seconds: 8);
