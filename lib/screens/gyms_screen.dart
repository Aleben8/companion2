import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../constants.dart';
import '../geo.dart';
import '../gyms.dart';
import '../mode.dart';
import '../services/battle_service.dart';
import '../services/gym_service.dart';
import '../services/item_service.dart';
import '../services/live_service.dart';
import '../services/location_service.dart';
import '../services/party_service.dart';
import '../services/session.dart';
import '../table/zones.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/clue_search.dart';
import '../widgets/drop.dart';

/// Mappa e lista delle palestre (tab della home). Se il giocatore sfida un
/// capopalestra chiama [onBattle] con l'id della battaglia appena creata.
class GymsTab extends StatefulWidget {
  final ValueChanged<String> onBattle;
  const GymsTab({super.key, required this.onBattle});
  @override
  State<GymsTab> createState() => _GymsTabState();
}

class _GymsTabState extends State<GymsTab> {
  String? _party;
  bool _master = false;
  bool _loading = true;
  bool _busy = false;

  Session get _s => context.read<Session>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      _party = await PartyService.actualParty(_s.userName!);
      if (_party != null) _master = await PartyService.isMaster(_party!, _s.userName!);
    } catch (e) {
      debugPrint('Errore caricamento palestre: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _run(Future<void> Function() f, {String? ok}) async {
    setState(() => _busy = true);
    try {
      await f();
      if (ok != null && mounted) snack(context, ok);
    } catch (e) {
      if (mounted) snack(context, '$e'.replaceFirst('Exception: ', ''), error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _launch(bool already) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(already ? 'Rigenera i capipalestra' : 'Avvia il gioco'),
        content: Text(already
            ? 'I capipalestra verranno rigenerati a caso (nuovi Pokémon e mosse). Posizioni calibrate e badge restano.'
            : 'Verranno creati i capipalestra nelle ${kGyms.length} location prestabilite, con Pokémon e mosse casuali coerenti con il tipo.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(already ? 'Rigenera' : 'Avvia')),
        ],
      ),
    );
    if (go != true) return;
    await _run(() => GymService.launch(_party!), ok: 'Capipalestra creati!');
  }

  Future<void> _calibrate(String gymId) => _run(() async {
        final p = await context.read<LocationService>().current();
        if (p == null) throw Exception('Posizione non disponibile');
        await GymService.calibrate(_party!, gymId, p.latitude, p.longitude);
      }, ok: 'Posizione della palestra impostata qui');

  Future<void> _challenge(String gymId, Map<String, dynamic> gym) => _run(() async {
        final loc = context.read<LocationService>();
        if (!kGymTestMode) {
          final p = await loc.current();
          if (p == null) throw Exception('Posizione non disponibile: attiva la localizzazione');
          final d = distanceMeters(p.latitude, p.longitude, (gym['lat'] as num).toDouble(), (gym['lng'] as num).toDouble());
          if (d > kGymRadiusMeters + p.accuracy.clamp(0, 30)) {
            throw Exception('Sei troppo lontano dalla palestra (${formatDistance(d)})');
          }
        }
        final id = await BattleService.createGymBattle(
          party: _party!,
          gymId: gymId,
          gym: gym,
          uid: _s.userName!,
          pk: _s.pokemonId!,
        );
        if (mounted) widget.onBattle(id);
      });

  /// Master: tiene premuto sulla mappa per posizionare (o spostare) una zona di gioco.
  Future<void> _placeZoneAt(LatLng p, Map<String, LiveZone> zones) async {
    final zone = await showDialog<ZoneSpec>(
      context: context,
      builder: (ctx) => SimpleDialog(title: const Text('Quale zona metti qui?'), children: [
        for (final z in kZones)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, z),
            child: Text('${z.name}${zones[z.id] == null ? '' : ' (sposta)'}'),
          ),
      ]),
    );
    if (zone == null || !mounted) return;
    final r = await showDialog<double>(
      context: context,
      builder: (ctx) => SimpleDialog(title: Text('Raggio di ${zone.name}'), children: [
        for (final r in kZoneRadiusChoices)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, r),
            child: Text('${r.round()} m${r == (zones[zone.id]?.radius ?? kDefaultZoneRadius) ? '  ✓' : ''}'),
          ),
      ]),
    );
    if (r == null) return;
    await _run(() => LiveService.setZone(_party!, zone.id, p.latitude, p.longitude, r), ok: '${zone.name} posizionata');
  }

  // ------------------------------------------------------------------ UI

  Widget _map(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, Map badges, Map<String, LiveZone> zones) {
    final pts = [
      ...docs.map((d) => LatLng((d['lat'] as num).toDouble(), (d['lng'] as num).toDouble())),
      ...zones.values.map((z) => LatLng(z.lat, z.lng)),
    ];
    final center = pts.isEmpty
        ? const LatLng(45.8190, 8.8250) // centro di Varese
        : LatLng(
            pts.map((p) => p.latitude).reduce((a, b) => a + b) / pts.length,
            pts.map((p) => p.longitude).reduce((a, b) => a + b) / pts.length,
          );
    return SizedBox(
      height: 300,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: FlutterMap(
          key: ValueKey('${docs.length}/${zones.length}'),
          options: MapOptions(
            initialCenter: center,
            initialZoom: 16,
            onLongPress: _master && !_busy ? (_, p) => _placeZoneAt(p, zones) : null,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'it.companion2.app',
            ),
            // zone di gioco (il tavolo dal vivo)
            CircleLayer(circles: [
              for (final z in zones.values)
                CircleMarker(
                  point: LatLng(z.lat, z.lng),
                  radius: z.radius,
                  useRadiusInMeter: true,
                  color: typeColors(zoneSpec(z.id).type).first.withOpacity(0.12),
                  borderColor: typeColors(zoneSpec(z.id).type).first,
                  borderStrokeWidth: 3,
                ),
            ]),
            CircleLayer(circles: [
              for (final d in docs)
                CircleMarker(
                  point: LatLng((d['lat'] as num).toDouble(), (d['lng'] as num).toDouble()),
                  radius: kGymRadiusMeters,
                  useRadiusInMeter: true,
                  color: (kTypeGradients[d['type']]?.first ?? Colors.grey).withOpacity(0.25),
                  borderColor: kTypeGradients[d['type']]?.first ?? Colors.grey,
                  borderStrokeWidth: 2,
                ),
            ]),
            MarkerLayer(markers: [
              for (final z in zones.values)
                Marker(
                  point: LatLng(z.lat, z.lng),
                  width: 130,
                  height: 26,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: typeColors(zoneSpec(z.id).type).first, width: 1.5),
                      ),
                      child: Text(zoneSpec(z.id).name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Pal.ink)),
                    ),
                  ),
                ),
              for (final d in docs)
                Marker(
                  point: LatLng((d['lat'] as num).toDouble(), (d['lng'] as num).toDouble()),
                  width: 46,
                  height: 46,
                  child: Tooltip(
                    message: (d['name'] ?? '').toString(),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(colors: kTypeGradients[d['type']] ?? kTypeGradients['Normale']!),
                        border: Border.all(color: badges[d.id] != null ? const Color(0xFFF4C542) : Colors.white, width: 3),
                      ),
                      child: TypeIcon((d['type'] ?? 'Normale').toString(), size: 28),
                    ),
                  ),
                ),
            ]),
            // solo questo strato si aggiorna a ogni posizione GPS (non tutta la mappa)
            Consumer<LocationService>(
              builder: (_, loc, __) {
                final pos = loc.position;
                return MarkerLayer(markers: [
                  if (pos != null)
                    Marker(
                      point: LatLng(pos.latitude, pos.longitude),
                      width: 22,
                      height: 22,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF2979FF),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                        ),
                      ),
                    ),
                ]);
              },
            ),
            const RichAttributionWidget(
              attributions: [TextSourceAttribution('© OpenStreetMap contributors')],
            ),
          ],
        ),
      ),
    );
  }

  Widget _gymCard(QueryDocumentSnapshot<Map<String, dynamic>> d, Position? pos, Map badges) {
    final g = d.data();
    final type = (g['type'] ?? 'Normale').toString();
    final colors = kTypeGradients[type] ?? kTypeGradients['Normale']!;
    final leader = g['leader'] as Map?;
    final has = badges[d.id] != null;
    double? dist;
    String? dir;
    if (pos != null) {
      final lat = (g['lat'] as num).toDouble();
      final lng = (g['lng'] as num).toDouble();
      dist = distanceMeters(pos.latitude, pos.longitude, lat, lng);
      dir = compass(pos.latitude, pos.longitude, lat, lng);
    }
    final inRange = kGymTestMode || (dist != null && dist <= kGymRadiusMeters + (pos?.accuracy.clamp(0, 30) ?? 0));
    const w = TextStyle(color: Colors.white);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(gradient: LinearGradient(colors: colors), borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 52,
            height: 52,
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(color: Pal.line, shape: BoxShape.circle),
            child: TypeIcon(type, size: 32),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text((g['name'] ?? '').toString(), style: w.copyWith(fontSize: 20, fontWeight: FontWeight.w600)),
              Text('Tipo $type', style: w.copyWith(fontSize: 13, color: Colors.white.withOpacity(0.85))),
            ]),
          ),
          if (has)
            const Chip(
              label: Text('BADGE ✓', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              backgroundColor: Color(0xFFF4C542),
              visualDensity: VisualDensity.compact,
            ),
        ]),
        const SizedBox(height: 10),
        Text('📍 ${g['address'] ?? ''}', style: w.copyWith(fontSize: 13)),
        if (leader != null)
          Text('Capopalestra: ${leader['trainer']}', style: w.copyWith(fontSize: 14, fontStyle: FontStyle.italic)),
        if (g['calibrated'] != true)
          Text('⚠️ Posizione provvisoria, da calibrare', style: w.copyWith(fontSize: 12, color: Colors.yellow.shade100)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: Text(
              dist == null ? 'Distanza non disponibile' : '${formatDistance(dist)} verso $dir',
              style: w.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: colors.first),
            onPressed: (_busy || !inRange) ? null : () => _challenge(d.id, g),
            child: Text(inRange ? 'Sfida' : 'Troppo lontano'),
          ),
        ]),
      ]),
    );
  }

  Widget _masterTools(bool started, List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: Pal.line, width: 2)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Avvio e calibrazione', style: TextStyle(color: Pal.ink, fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text(
          'Solo chi ha il ruolo di Master vede questa sezione: serve unicamente a preparare il gioco. '
          'Poi tutti giocano alla pari.',
          style: TextStyle(color: Pal.sub, fontSize: 12),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _busy ? null : () => _launch(started),
          icon: const Icon(Icons.rocket_launch),
          label: Text(started ? 'Rigenera capipalestra' : 'Avvia il gioco'),
        ),
        if (docs.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Text('Posizioni: mettiti sul posto e premi "Imposta qui".',
              style: TextStyle(color: Pal.sub, fontSize: 13)),
          for (final d in docs)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text((d['name'] ?? '').toString(), style: const TextStyle(color: Pal.ink)),
              subtitle: Text(d['calibrated'] == true ? 'Calibrata ✓' : 'Provvisoria',
                  style: TextStyle(color: d['calibrated'] == true ? Pal.ok : Pal.warn)),
              trailing: TextButton(onPressed: _busy ? null : () => _calibrate(d.id), child: const Text('Imposta qui')),
            ),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
    }
    if (_party == null) {
      return const Padding(
        padding: EdgeInsets.all(30),
        child: Center(child: Text('Entra prima in un party', style: TextStyle(color: Pal.sub))),
      );
    }
    // solo i badge: la posizione GPS scritta sul profilo non deve ricostruire mappa e schede
    return StreamBuilder<Map<String, dynamic>>(
      stream: ItemService.watchUserFields(_s.userName!, const ['badges']),
      builder: (context, userSnap) {
        final raw = userSnap.data?['badges'];
        final badges = raw is Map ? raw : const {};
        return StreamBuilder<bool>(
          stream: GymService.watchStarted(_party!),
          builder: (context, startedSnap) {
            final started = startedSnap.data == true;
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: GymService.watchGyms(_party!),
              builder: (context, snap) {
                final docs = snap.data?.docs ?? [];
                return Column(children: [
                  const SectionTitle('Mappa'),
                  const SizedBox(height: 6),
                  StreamBuilder<Map<String, LiveZone>>(
                    stream: LiveService.watchZones(_party!),
                    builder: (context, zSnap) => _map(docs, badges, zSnap.data ?? const {}),
                  ),
                  if (_master)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text('Master: tieni premuto sulla mappa per posizionare una zona.',
                          style: TextStyle(color: Pal.sub, fontSize: 12)),
                    ),
                  const SizedBox(height: 8),
                  ClueSearchButton(party: _party!, uid: _s.userName!),
                  const SizedBox(height: 8),
                  if (_master) _masterTools(started, docs),
                  if (!started)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'Il gioco non è ancora stato avviato: i capipalestra compariranno quando verrà lanciato.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Pal.sub),
                      ),
                    ),
                  // le distanze cambiano a ogni posizione GPS: si ricostruiscono solo le schede
                  Consumer<LocationService>(
                    builder: (_, loc, __) => Column(children: [for (final d in docs) _gymCard(d, loc.position, badges)]),
                  ),
                ]);
              },
            );
          },
        );
      },
    );
  }
}
