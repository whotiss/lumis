import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../auth_state.dart';
import '../models.dart';
import '../sparkle.dart';
import '../theme.dart';
import '../widgets.dart';

/// Places in the Klang Valley where a dermatologist practises (FR6). Sorted by distance when the person allowed
/// location; otherwise A to Z. The location is only used to sort and is never stored (consent text).
class ClinicsScreen extends StatefulWidget {
  const ClinicsScreen({super.key});

  @override
  State<ClinicsScreen> createState() => _ClinicsScreenState();
}

/// Filter buttons, in the order shown. null = all kinds.
const _filters = <(String?, String)>[
  (null, 'All'),
  ('government_hospital', 'Government'),
  ('private_hospital', 'Private hospitals'),
  ('specialist_clinic', 'Skin clinics'),
  ('university_hospital', 'University'),
];

class _ClinicsScreenState extends State<ClinicsScreen> {
  ClinicList? _list;
  String? _error;
  String? _note; // why the list is not sorted by distance
  bool _byDistance = false;
  LatLng? _me;
  String? _type;

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
          _me = null;
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
          _me = LatLng(position.latitude, position.longitude);
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
    final p = context.palette;
    final shown = list?.clinics.where((c) => _type == null || c.type == _type).toList() ?? <Clinic>[];

    // With everything shown and sorted by distance: the three nearest, then the nearest government hospital
    // (lower cost, needs a referral letter) if it is not already among them, then the rest.
    Clinic? lowerCost;
    if (_byDistance && _type == null && shown.length > 3) {
      final firstGov = shown.indexWhere((c) => c.type == 'government_hospital');
      if (firstGov >= 3) lowerCost = shown[firstGov];
    }
    final nearest = lowerCost == null ? shown : shown.take(3).toList();
    final rest = lowerCost == null ? <Clinic>[] : shown.skip(3).where((c) => c != lowerCost).toList();

    return Scaffold(
      appBar: lumisAppBar(context,
          title: _byDistance ? 'Dermatologists near you' : 'Dermatologists',
          subtitle: list == null
              ? null
              : '${list.clinics.length} places in the Klang Valley${_byDistance ? ', nearest first' : ', A to Z'}'),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _byDistance ? _loadNearby : _loadAll)
          : list == null
              ? const Center(child: Sparkle(size: 56, animate: true))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
                  children: [
                    if (list.outsideCoverage) ...[
                      const DisclaimerBanner('You seem to be outside the Klang Valley, which is all this list covers. '
                          'For other states, see the Persatuan Dermatologi Malaysia directory at dermatology.org.my.'),
                      const SizedBox(height: 12),
                    ],
                    _MapPreview(
                      clinics: shown,
                      me: _me,
                      onExpand: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => _FullMap(clinics: shown, me: _me)),
                      ),
                    ),
                    if (!_byDistance) ...[
                      const SizedBox(height: 12),
                      if (_note != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(_note!, style: TextStyle(fontSize: 13, color: p.muted)),
                        ),
                      LumisButton.secondary(
                        label: 'Sort by distance from me',
                        icon: Icons.my_location_rounded,
                        onPressed: (context.read<AuthState>().user?.consentLocation ?? false)
                            ? _loadNearby
                            : _askForLocation,
                      ),
                    ],
                    const SizedBox(height: 14),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      clipBehavior: Clip.none,
                      child: Row(children: [
                        for (final (value, label) in _filters)
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
                    const SizedBox(height: 14),
                    for (final c in nearest) ...[_ClinicCard(c), const SizedBox(height: 10)],
                    if (lowerCost != null) ...[
                      const SizedBox(height: 6),
                      const SectionLabel('Lower-cost option'),
                      const SizedBox(height: 10),
                      _ClinicCard(lowerCost, highlight: true),
                      const SizedBox(height: 16),
                      const SectionLabel('More places'),
                      const SizedBox(height: 10),
                      for (final c in rest) ...[_ClinicCard(c), const SizedBox(height: 10)],
                    ],
                    if (shown.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text('No places of this kind.', textAlign: TextAlign.center, style: TextStyle(color: p.muted)),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      'Places where a dermatologist practises, from the Persatuan Dermatologi Malaysia directory '
                      '(checked ${list.checked}). Lumis does not rank or recommend any of them. '
                      '${_byDistance ? 'Distances are in a straight line, not by road. Your location is only used to '
                          'sort this list and is never stored. ' : ''}Call before you go, as hours and doctors change. '
                      '${list.attribution}.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
    );
  }
}

const _tileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const _userAgent = 'my.lumis.lumis'; // OpenStreetMap asks apps to identify themselves
final _klangValley = LatLng(3.1, 101.62);

List<Marker> _markers(List<Clinic> clinics, LatLng? me, LumisPalette p) => [
      for (final c in clinics.take(40))
        if (c.lat != null && c.lon != null)
          Marker(
            point: LatLng(c.lat!, c.lon!),
            width: 26,
            height: 26,
            child: Tooltip(
              message: c.name,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: p.cardTop.withValues(alpha: 0.92),
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: p.shadow, blurRadius: 4)],
                ),
                child: const Padding(padding: EdgeInsets.all(5), child: Sparkle(size: 16, style: SparkleStyle.low)),
              ),
            ),
          ),
      if (me != null)
        Marker(
          point: me,
          width: 18,
          height: 18,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: p.isDark ? p.buttonBottom : p.accent,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: [BoxShadow(color: p.accent.withValues(alpha: 0.4), blurRadius: 10, spreadRadius: 2)],
            ),
          ),
        ),
    ];

MapOptions _mapOptions(List<Clinic> clinics, LatLng? me, {required bool interactive}) {
  final points = [
    if (me != null) me,
    for (final c in clinics.take(me == null ? 40 : 4))
      if (c.lat != null && c.lon != null) LatLng(c.lat!, c.lon!),
  ];
  return MapOptions(
    initialCenter: me ?? _klangValley,
    initialZoom: me == null ? 10.5 : 13,
    initialCameraFit: points.length >= 2
        ? CameraFit.coordinates(coordinates: points, padding: const EdgeInsets.all(34), maxZoom: 15)
        : null,
    interactionOptions: InteractionOptions(flags: interactive ? InteractiveFlag.all & ~InteractiveFlag.rotate : InteractiveFlag.none),
  );
}

TileLayer _tiles(LumisPalette p) => TileLayer(
      urlTemplate: _tileUrl,
      userAgentPackageName: _userAgent,
      tileBuilder: p.isDark ? darkModeTileBuilder : null,
    );

class _MapPreview extends StatelessWidget {
  const _MapPreview({required this.clinics, required this.me, required this.onExpand});
  final List<Clinic> clinics;
  final LatLng? me;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      label: 'Map of the places in the list',
      child: Container(
        height: 210,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: p.nebulaBorder),
          boxShadow: [BoxShadow(color: p.shadow, blurRadius: 18, offset: const Offset(0, 6))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(children: [
            FlutterMap(
              key: ValueKey('${me?.latitude}-${clinics.length}'),
              options: _mapOptions(clinics, me, interactive: false),
              children: [_tiles(p), MarkerLayer(markers: _markers(clinics, me, p))],
            ),
            if (me != null)
              Positioned(left: 10, top: 10, child: _MapChip(child: Text('You are here', style: TextStyle(fontSize: 12, color: p.ink)))),
            Positioned(
              left: 10,
              bottom: 8,
              child: Text('© OpenStreetMap', style: TextStyle(fontSize: 10, color: p.isDark ? p.muted : p.faint)),
            ),
            Positioned(
              right: 10,
              bottom: 10,
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: onExpand,
                  borderRadius: BorderRadius.circular(7),
                  child: _MapChip(
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.open_in_full_rounded, size: 14, color: p.ink),
                      const SizedBox(width: 6),
                      Text('Full map', style: TextStyle(fontSize: 13, color: p.ink)),
                    ]),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _MapChip extends StatelessWidget {
  const _MapChip({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        gradient: p.cardGradient,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: p.border),
        boxShadow: [BoxShadow(color: p.shadow, blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: child,
    );
  }
}

class _FullMap extends StatelessWidget {
  const _FullMap({required this.clinics, required this.me});
  final List<Clinic> clinics;
  final LatLng? me;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      appBar: lumisAppBar(context, title: 'Map'),
      body: FlutterMap(
        options: _mapOptions(clinics, me, interactive: true),
        children: [
          _tiles(p),
          MarkerLayer(markers: _markers(clinics, me, p)),
          RichAttributionWidget(
            attributions: [
              TextSourceAttribution('OpenStreetMap contributors',
                  onTap: () => launchUrl(Uri.parse('https://www.openstreetmap.org/copyright'))),
            ],
          ),
        ],
      ),
    );
  }
}

class _ClinicCard extends StatelessWidget {
  const _ClinicCard(this.c, {this.highlight = false});
  final Clinic c;
  final bool highlight;

  static const _shortTypes = {
    'government_hospital': 'Government hospital',
    'university_hospital': 'University hospital',
    'private_hospital': 'Private hospital',
    'specialist_clinic': 'Skin specialist clinic',
  };

  Future<void> _open(BuildContext context, Uri uri) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && context.mounted) {
      showMessage(context, 'Could not open $uri');
    }
  }

  Uri get _directions {
    final lat = c.lat, lon = c.lon;
    if (Platform.isIOS) {
      return Uri.https('maps.apple.com', '/', {
        if (lat != null && lon != null) 'daddr': '$lat,$lon' else 'daddr': '${c.name}, ${c.address}',
        'q': c.name,
      });
    }
    return Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': lat != null && lon != null ? '$lat,$lon' : '${c.name}, ${c.address}',
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    final needsReferral = c.type == 'government_hospital' || c.type == 'university_hospital';
    final buttons = <Widget>[
      if (c.phone != null)
        _SmallButton(
          label: 'Call',
          icon: Icons.call_outlined,
          style: highlight ? _SmallStyle.outline : _SmallStyle.primary,
          onTap: () => _open(context, Uri(scheme: 'tel', path: c.phone!.replaceAll(RegExp(r'[^0-9+]'), ''))),
        ),
      _SmallButton(
        label: 'Directions',
        icon: Icons.near_me_outlined,
        style: highlight ? _SmallStyle.outline : _SmallStyle.soft,
        onTap: () => _open(context, _directions),
      ),
      if (c.website != null)
        _SmallButton(
          label: 'Website',
          icon: Icons.language_rounded,
          style: _SmallStyle.outline,
          onTap: () => _open(context, Uri.parse(c.website!)),
        ),
    ];
    return Panel(
      tone: highlight ? PanelTone.nebula : PanelTone.paper,
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.name, style: t.titleMedium),
              Text('${_shortTypes[c.type] ?? c.typeLabel} · ${c.city}',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w300, color: p.muted)),
            ]),
          ),
          if (c.distanceKm != null) ...[
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(c.distanceKm!.toStringAsFixed(1),
                  style: TextStyle(fontFamily: headingFont, fontSize: 20, height: 1, color: p.ink)),
              Text('km', style: TextStyle(fontSize: 11, color: p.faint)),
            ]),
          ],
        ]),
        if (c.childrenOnly) ...[
          const SizedBox(height: 8),
          Text('Children only', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: p.accent)),
        ],
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (needsReferral) ...[
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 8),
              child: Icon(Icons.description_outlined, size: 15, color: p.nebulaText),
            ),
          ],
          Expanded(
            child: Text(c.access,
                style: TextStyle(fontSize: 13, height: 1.45, fontWeight: FontWeight.w300, color: needsReferral ? p.nebulaText : p.body)),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          for (var i = 0; i < buttons.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: buttons[i]),
          ],
        ]),
      ]),
    );
  }
}

enum _SmallStyle { primary, soft, outline }

class _SmallButton extends StatelessWidget {
  const _SmallButton({required this.label, required this.icon, required this.style, required this.onTap});
  final String label;
  final IconData icon;
  final _SmallStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (Gradient? gradient, Color? fill, Color? border, Color fg) = switch (style) {
      _SmallStyle.primary => (p.buttonGradient, null, null, p.onButton),
      _SmallStyle.soft => (null, p.nebulaTop, p.nebulaBorder, p.nebulaText),
      _SmallStyle.outline => (null, p.cardTop, p.border, p.ink),
    };
    final r = BorderRadius.circular(7);
    return Semantics(
      button: true,
      label: label,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: gradient,
          color: fill,
          borderRadius: r,
          border: border == null ? null : Border.all(color: border),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: r,
            onTap: onTap,
            child: SizedBox(
              height: 42,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, size: 15, color: fg),
                const SizedBox(width: 6),
                Flexible(
                  child: ExcludeSemantics(
                    child: Text(label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: fg)),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
