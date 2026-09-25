import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../models/proposal.dart';
import '../models/ward.dart';
import '../theme.dart';
import '../utils/categories.dart';
import 'common.dart';

/// Default map centre when a ward has none (Chennai).
const kDefaultCenter = LatLng(13.0827, 80.2707);

LatLng wardCenter(Ward? w) =>
    (w?.centerLat != null && w?.centerLng != null) ? LatLng(w!.centerLat!, w.centerLng!) : kDefaultCenter;

LatLng? proposalPoint(Proposal p) => p.hasLocation ? LatLng(p.lat!, p.lng!) : null;

/// Off in offline screenshot tests (no network there).
bool mapTilesEnabled = true;

/// Calm green look for the busy OpenStreetMap style: half desaturated, then a
/// light green tint, so pins stand out and street labels stay readable.
const _greenTint = ColorFilter.matrix(<double>[
  0.56, 0.33, 0.03, 0, 6, //
  0.10, 0.84, 0.04, 0, 12,
  0.10, 0.33, 0.49, 0, 8,
  0, 0, 0, 1, 0,
]);

/// Basemap: OpenStreetMap standard tiles (free, no API key; the tile policy
/// requires a real User-Agent and the attribution shown by [osmAttribution]).
/// Note: CARTO basemaps now need an API key, so they are not used.
List<Widget> osmLayers() => [
      if (mapTilesEnabled)
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'app.namnagaram',
          maxZoom: 19,
          tileBuilder: (context, tile, _) => ColorFiltered(colorFilter: _greenTint, child: tile),
        ),
    ];

const osmAttribution = SimpleAttributionWidget(
  source: Text('OpenStreetMap contributors'),
  backgroundColor: Color(0xCCFFFFFF),
);

/// Map background while tiles load (mint instead of grey).
const kMapBackground = Color(0xFFE6F0EA);

/// Pin colour by review status.
Color pinColor(Proposal p) => switch (p.status) {
      ProposalStatus.approved => AppColors.forest,
      ProposalStatus.pending => const Color(0xFFD08A00),
      ProposalStatus.rejected => const Color(0xFF8A9A91),
    };

/// Teardrop map pin with the proposal's category icon.
class ProposalPin extends StatelessWidget {
  const ProposalPin({super.key, required this.proposal, this.selected = false, this.onBallot = false});

  final Proposal proposal;
  final bool selected;
  final bool onBallot;

  static const size = Size(46, 56);

  @override
  Widget build(BuildContext context) {
    final color = pinColor(proposal);
    return AnimatedScale(
      scale: selected ? 1.25 : 1,
      duration: const Duration(milliseconds: 180),
      alignment: Alignment.bottomCenter,
      child: Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
        CustomPaint(size: size, painter: _PinPainter(color: color, ring: selected)),
        Positioned(
          top: 8,
          child: Icon(categoryIcon(proposal.category), size: 20, color: Colors.white),
        ),
        if (onBallot)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: AppColors.leaf,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Icon(Icons.check_rounded, size: 11, color: AppColors.forestDark),
            ),
          ),
      ]),
    );
  }
}

class _PinPainter extends CustomPainter {
  _PinPainter({required this.color, required this.ring});

  final Color color;
  final bool ring;

  @override
  void paint(Canvas canvas, Size s) {
    final r = s.width / 2;
    final path = Path()
      ..moveTo(s.width / 2, s.height)
      ..quadraticBezierTo(s.width * 0.18, s.height * 0.62, 0, r)
      ..arcToPoint(Offset(s.width, r), radius: Radius.circular(r))
      ..quadraticBezierTo(s.width * 0.82, s.height * 0.62, s.width / 2, s.height)
      ..close();
    canvas.drawShadow(path, Colors.black, 3, false);
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..color = ring ? AppColors.leaf : Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = ring ? 3 : 2,
    );
  }

  @override
  bool shouldRepaint(_PinPainter old) => old.color != color || old.ring != ring;
}

/// Marker for a proposal: pin whose tip sits on the point, name label under it.
Marker proposalMarker(Proposal p, {bool selected = false, bool onBallot = false, bool label = true, VoidCallback? onTap}) {
  const pinBox = 68.0; // pin (56) + padding
  return Marker(
    point: proposalPoint(p)!,
    width: 150,
    height: pinBox * 2,
    alignment: Alignment.center, // top half = pin (tip on the point), bottom half = label
    child: GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.deferToChild,
      child: Column(children: [
        SizedBox(
          height: pinBox,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ProposalPin(proposal: p, selected: selected, onBallot: onBallot),
          ),
        ),
        if (label) ...[
          const SizedBox(height: 4),
          _PinLabel(text: p.title, selected: selected, color: pinColor(p)),
        ],
      ]),
    ),
  );
}

/// Small name tag under a pin.
class _PinLabel extends StatelessWidget {
  const _PinLabel({required this.text, required this.selected, required this.color});

  final String text;
  final bool selected;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(maxWidth: 140),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: selected ? color : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? Colors.white : color.withValues(alpha: 0.35)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            color: selected ? Colors.white : AppColors.forestDark,
          ),
        ),
      );
}

/// Small, non-interactive map with one pin (proposal detail). Tap → [onOpen].
class MiniMap extends StatelessWidget {
  const MiniMap({super.key, required this.proposal, this.onOpen});

  final Proposal proposal;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          height: 170,
          child: Stack(children: [
            FlutterMap(
              options: MapOptions(
                backgroundColor: kMapBackground,
                initialCenter: proposalPoint(proposal)!,
                initialZoom: 15.5,
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                onTap: (_, _) => onOpen?.call(),
              ),
              children: [
                ...osmLayers(),
                MarkerLayer(markers: [proposalMarker(proposal, label: false, onTap: onOpen)]),
                osmAttribution,
              ],
            ),
            if (onOpen != null)
              Positioned(
                right: 10,
                top: 10,
                child: Material(
                  color: Colors.white,
                  shape: const StadiumBorder(),
                  elevation: 2,
                  child: InkWell(
                    customBorder: const StadiumBorder(),
                    onTap: onOpen,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.open_in_full_rounded, size: 15, color: AppColors.forest),
                        SizedBox(width: 6),
                        Text('Open map',
                            style: TextStyle(color: AppColors.forest, fontWeight: FontWeight.w700, fontSize: 12.5)),
                      ]),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      );
}

/// Full-screen picker: pan the map under the fixed centre pin, then confirm.
/// Pops with the chosen [LatLng].
class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({super.key, required this.initial, this.title = 'Pick the location'});

  final LatLng initial;
  final String title;

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  late LatLng _center = widget.initial;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: Stack(children: [
          FlutterMap(
            options: MapOptions(
              backgroundColor: kMapBackground,
              initialCenter: widget.initial,
              initialZoom: 16,
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
              onPositionChanged: (camera, _) => _center = camera.center,
            ),
            children: [...osmLayers(), osmAttribution],
          ),
          // Fixed pin in the middle; its tip marks the spot.
          IgnorePointer(
            child: Center(
              child: Transform.translate(
                offset: const Offset(0, -28),
                child: CustomPaint(size: ProposalPin.size, painter: _PinPainter(color: AppColors.forest, ring: true)),
              ),
            ),
          ),
          const Positioned(
            left: 16,
            right: 16,
            top: 12,
            child: MessageBanner('Drag the map so the pin sits on the exact spot.', isError: false),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: SafeArea(
              child: PrimaryButton(
                label: 'Use this location',
                icon: Icons.place_rounded,
                onPressed: () => Navigator.pop(context, _center),
              ),
            ),
          ),
        ]),
      );
}

/// Legend chips for the map.
class MapLegend extends StatelessWidget {
  const MapLegend({super.key, this.showRejected = false});

  final bool showRejected;

  @override
  Widget build(BuildContext context) {
    Widget item(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(t, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.ink)),
        ]);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8)],
      ),
      child: Wrap(spacing: 12, runSpacing: 4, children: [
        item(AppColors.forest, 'On ballot'),
        item(const Color(0xFFD08A00), 'Idea in review'),
        if (showRejected) item(const Color(0xFF8A9A91), 'Not approved'),
      ]),
    );
  }
}
