import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../auth_state.dart';
import '../models.dart';
import '../widgets.dart';

/// Places in the Klang Valley where a dermatologist practises (FR6). Sorted by distance when the person allowed
/// location; otherwise A to Z. The location is only used to sort and is never stored (consent text).
class ClinicsScreen extends StatefulWidget {
  const ClinicsScreen({super.key});

  @override
  State<ClinicsScreen> createState() => _ClinicsScreenState();
}

class _ClinicsScreenState extends State<ClinicsScreen> {
  ClinicList? _list;
  String? _error;
  String? _note; // why the list is not sorted by distance
  bool _byDistance = false;
  String? _type; // filter; null = all kinds

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthState>().user;
    if (user?.consentLocation ?? false) {
      _loadNearby();
    } else {
      _loadAll();
    }
  }

  Future<void> _loadAll({String? note}) async {
    if (!mounted) return;
    setState(() {
      _error = null;
      _note = note;
    });
    try {
      final list = await context.read<Api>().clinics();
      if (mounted) {
        setState(() {
          _list = list;
          _byDistance = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _loadNearby() async {
    final api = context.read<Api>();
    setState(() {
      _error = null;
      _list = null;
    });
    final Position position;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return await _loadAll(note: 'Location is turned off on your phone, so the list is A to Z.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        return await _loadAll(note: 'Lumis was not allowed to use your location, so the list is A to Z.');
      }
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 15)),
      );
    } catch (_) {
      return _loadAll(note: 'Your location could not be found, so the list is A to Z.');
    }
    try {
      final list = await api.nearbyClinics(position.latitude, position.longitude, limit: 30);
      if (mounted) {
        setState(() {
          _list = list;
          _byDistance = true;
          _note = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _askForLocation() async {
    final ok = await confirm(context,
        title: 'Use your location?',
        body: 'Lumis uses your location only to sort clinics by distance. It is not stored. '
            'You can turn this off in Settings.',
        action: 'Use my location');
    if (!ok || !mounted) return;
    try {
      await context.read<AuthState>().updateConsent(location: true);
      if (mounted) await _loadNearby();
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    final shown = list?.clinics.where((c) => _type == null || c.type == _type).toList() ?? [];
    return Scaffold(
      appBar: AppBar(title: const Text('Find a dermatologist')),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _byDistance ? _loadNearby : _loadAll)
          : list == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (list.outsideCoverage) ...[
                      const DisclaimerBanner('You seem to be outside the Klang Valley, which is all this list covers. '
                          'For other states, see the Persatuan Dermatologi Malaysia directory at dermatology.org.my.'),
                      const SizedBox(height: 12),
                    ],
                    if (!_byDistance) ...[
                      if (_note != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_note!)),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.my_location),
                        label: const Text('Sort by distance from me'),
                        onPressed: (context.read<AuthState>().user?.consentLocation ?? false)
                            ? _loadNearby
                            : _askForLocation,
                      ),
                      const SizedBox(height: 12),
                    ],
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: [
                        for (final (value, label) in <(String?, String)>[
                          (null, 'All'),
                          for (final e in Clinic.typeLabels.entries) (e.key, e.value),
                        ])
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(label),
                              selected: _type == value,
                              onSelected: (_) => setState(() => _type = value),
                            ),
                          ),
                      ]),
                    ),
                    const SizedBox(height: 12),
                    for (final c in shown) ...[_ClinicCard(c), const SizedBox(height: 10)],
                    if (shown.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('No places of this kind.')),
                    const SizedBox(height: 8),
                    Text(
                      'Places where a dermatologist practises, from the Persatuan Dermatologi Malaysia directory '
                      '(checked ${list.checked}). Lumis does not rank or recommend any of them. '
                      '${_byDistance ? 'Distances are in a straight line, not by road. ' : ''}${list.attribution}.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
    );
  }
}

class _ClinicCard extends StatelessWidget {
  const _ClinicCard(this.c);
  final Clinic c;

  Future<void> _open(BuildContext context, Uri uri) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && context.mounted) {
      showMessage(context, 'Could not open $uri');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final maps = Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': '${c.name}, ${c.address}'});
    return InfoCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(c.name, style: t.titleMedium),
        const SizedBox(height: 4),
        Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(c.typeLabel, style: t.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
          if (c.distanceKm != null) Text('${c.distanceKm!.toStringAsFixed(1)} km away', style: t.bodySmall),
          if (c.childrenOnly)
            const Chip(label: Text('Children only'), visualDensity: VisualDensity.compact),
        ]),
        const SizedBox(height: 8),
        Text(c.address),
        const SizedBox(height: 6),
        Text(c.access, style: t.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          if (c.phone != null)
            TextButton.icon(
              icon: const Icon(Icons.call_outlined),
              label: const Text('Call'),
              onPressed: () => _open(context, Uri(scheme: 'tel', path: c.phone!.replaceAll(RegExp(r'[^0-9+]'), ''))),
            ),
          TextButton.icon(
            icon: const Icon(Icons.directions_outlined),
            label: const Text('Directions'),
            onPressed: () => _open(context, maps),
          ),
          if (c.website != null)
            TextButton.icon(
              icon: const Icon(Icons.open_in_new),
              label: const Text('Website'),
              onPressed: () => _open(context, Uri.parse(c.website!)),
            ),
        ]),
      ]),
    );
  }
}
