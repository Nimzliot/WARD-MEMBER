import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/proposal.dart';
import '../models/ward.dart';
import '../providers/ward_provider.dart';
import '../services/api_service.dart';
import '../theme.dart';
import '../utils/categories.dart';
import '../utils/errors.dart';
import '../utils/format.dart';
import '../widgets/civic.dart';
import '../widgets/common.dart';
import '../widgets/failure_view.dart';
import '../widgets/map_widgets.dart';
import 'proposal_form_screen.dart';

enum _Metric { cost, votes }

/// Admin → 3D map: every proposal and idea in every ward as a 3D pillar rising
/// from a tilted map. Pillar height = cost or votes; colour = review status.
/// With [homeWard] set (ward members) it is locked to that ward and read-only.
class AdminMapScreen extends StatefulWidget {
  const AdminMapScreen({super.key, this.homeWard});

  final int? homeWard;

  @override
  State<AdminMapScreen> createState() => _AdminMapScreenState();
}

class _AdminMapScreenState extends State<AdminMapScreen> with SingleTickerProviderStateMixin {
  final _map = MapController();
  late final AnimationController _tilt =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100), value: 0);
  StreamSubscription<MapEvent>? _mapEvents;

  List<Ward> _wards = [];
  List<Proposal> _proposals = [];
  Map<String, int> _votes = {};
  bool _loading = true;
  Object? _error;
  bool _mapReady = false;

  late int? _ward = widget.homeWard; // null = all wards
  bool get _resident => widget.homeWard != null;
  _Metric _metric = _Metric.cost;
  bool _threeD = true;
  String? _selectedId;

  static const _maxTilt = 0.95; // radians the ground leans back in 3D

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _mapEvents?.cancel();
    _tilt.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sb = Supabase.instance.client;
      final r = await Future.wait<dynamic>([
        sb.from('wards').select().order('id', ascending: true),
        sb.from('proposals').select('*, budget_items(*)').order('created_at', ascending: true),
        sb.from('votes').select('proposal_ids'),
      ]);
      final votes = <String, int>{};
      for (final v in r[2] as List) {
        for (final id in ((v as Map)['proposal_ids'] as List).cast<String>()) {
          votes[id] = (votes[id] ?? 0) + 1;
        }
      }
      if (!mounted) return;
      setState(() {
        _wards = [for (final w in r[0] as List) Ward.fromMap(w as Map<String, dynamic>)];
        _proposals = [for (final p in r[1] as List) Proposal.fromMap(p as Map<String, dynamic>)];
        _votes = votes;
        _loading = false;
      });
      if (_threeD) _tilt.forward(from: 0); // fly into 3D once data is in
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  List<Proposal> get _visible =>
      _proposals.where((p) => p.hasLocation && (_ward == null || p.wardId == _ward)).toList();

  double _metricOf(Proposal p) => _metric == _Metric.cost ? p.totalCost.toDouble() : (_votes[p.id] ?? 0).toDouble();

  String _metricLabel(Proposal p) => _metric == _Metric.cost
      ? inrCompact(p.totalCost)
      : '${_votes[p.id] ?? 0} vote${(_votes[p.id] ?? 0) == 1 ? '' : 's'}';

  String _wardName(int id) =>
      _wards.where((w) => w.id == id).firstOrNull?.name.split('–').first.trim() ?? 'Ward $id';

  void _fit() {
    if (!_mapReady) return;
    final pts = [for (final p in _visible) proposalPoint(p)!];
    if (pts.isEmpty) {
      final w = _wards.where((w) => w.id == _ward).firstOrNull;
      _map.move(wardCenter(w), 14);
    } else if (pts.length == 1) {
      _map.move(pts.first, 15.5);
    } else {
      _map.fitCamera(CameraFit.coordinates(
        coordinates: pts,
        padding: const EdgeInsets.fromLTRB(40, 150, 40, 170),
        maxZoom: 16,
      ));
    }
    // In 3D the tilted, scaled ground magnifies the view: zoom out so every pillar fits.
    if (_threeD) _map.move(_map.camera.center, _map.camera.zoom - 1.1);
  }

  void _setWard(int? id) {
    setState(() {
      _ward = id;
      _selectedId = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _fit());
  }

  void _toggle3D() {
    setState(() => _threeD = !_threeD);
    _threeD ? _tilt.forward() : _tilt.reverse();
    _fit();
  }

  Future<void> _approve(Proposal p) async {
    try {
      await ApiService.patch('/api/admin/proposals/${p.id}', {'status': 'approved'});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Approved: "${p.title}" is on the ballot')));
      context.read<WardProvider>().load();
      await _load();
    } catch (e) {
      if (mounted && !await showFailure(context, e) && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  Future<void> _edit(Proposal p) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ProposalFormScreen(mode: ProposalFormMode.edit, proposal: p)),
    );
    if (saved == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(body: SafeArea(child: ErrorView(error: _error, onRetry: _load)));
    }
    final visible = _visible;
    final selected = visible.where((p) => p.id == _selectedId).firstOrNull;
    final pending = visible.where((p) => p.status == ProposalStatus.pending).length;
    final onBallot = visible.where((p) => p.isApproved).length;
    final asked = visible.where((p) => p.isApproved).fold<int>(0, (s, p) => s + p.totalCost);
    final unpinned = _proposals.where((p) => !p.hasLocation && (_ward == null || p.wardId == _ward)).length;

    return Scaffold(
      backgroundColor: AppColors.forestDark,
      body: Stack(children: [
        // ---------------- tilted ground + upright pillars ----------------
        Positioned.fill(
          child: LayoutBuilder(builder: (context, box) {
            final size = box.biggest;
            final origin = Offset(size.width / 2, size.height * 0.62);
            return AnimatedBuilder(
              animation: _tilt,
              builder: (context, _) {
                final t = Curves.easeInOutCubic.transform(_tilt.value);
                final m = Matrix4.identity()
                  ..setEntry(3, 2, 0.0011 * t)
                  ..rotateX(-_maxTilt * t)
                  ..scaleByDouble(1 + 0.35 * t, 1 + 0.35 * t, 1, 1);
                final full = Matrix4.translationValues(origin.dx, origin.dy, 0)
                  ..multiply(m)
                  ..multiply(Matrix4.translationValues(-origin.dx, -origin.dy, 0));
                return Stack(children: [
                  // sky / horizon behind the tilted plane
                  const Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [AppColors.forestDark, AppColors.forest, Color(0xFF2E7D5B)],
                          stops: [0, 0.35, 0.6],
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: CustomPaint(painter: KolamPatternPainter(opacity: 0.06 * t, cell: 34)),
                  ),
                  Positioned.fill(
                    child: Transform(
                      transform: m,
                      origin: origin,
                      child: ClipRect(
                        child: FlutterMap(
                          mapController: _map,
                          options: MapOptions(
                            backgroundColor: kMapBackground,
                            initialCenter: wardCenter(_wards.firstOrNull),
                            initialZoom: 12.5,
                            interactionOptions:
                                const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                            onMapReady: () {
                              _mapReady = true;
                              _mapEvents = _map.mapEventStream.listen((_) {
                                if (mounted) setState(() {}); // re-project pillars
                              });
                              WidgetsBinding.instance.addPostFrameCallback((_) => _fit());
                            },
                            onTap: (_, _) => setState(() => _selectedId = null),
                          ),
                          children: [...osmLayers()],
                        ),
                      ),
                    ),
                  ),
                  // distance fog: fades the far edge into the horizon
                  IgnorePointer(
                    child: Container(
                      height: size.height * 0.42 * t,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [AppColors.forestDark.withValues(alpha: 0.9 * t), AppColors.forestDark.withValues(alpha: 0)],
                        ),
                      ),
                    ),
                  ),
                  if (_mapReady) ..._pillars(visible, full, size, t),
                ]);
              },
            );
          }),
        ),

        // ---------------- floating top bar ----------------
        Positioned(left: 0, right: 0, top: MediaQuery.paddingOf(context).top, child: const TricolourStrip(height: 3)),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _glass(Row(children: [
                IconButton(
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                ),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Ward map · 3D',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
                    Text(
                      '${_ward == null ? 'All wards' : _wardName(_ward!)} · ${visible.length} pinned'
                      '${unpinned > 0 ? ' · $unpinned without a pin' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 12),
                    ),
                  ]),
                ),
                const SizedBox(width: 8),
              ])),
              const SizedBox(height: 10),
              if (!_resident) ...[
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    _chip('All wards', _ward == null, () => _setWard(null)),
                    for (final w in _wards) _chip(_wardName(w.id), _ward == w.id, () => _setWard(w.id)),
                  ]),
                ),
                const SizedBox(height: 8),
              ],
              Row(children: [
                _toolButton(_threeD ? Icons.layers_rounded : Icons.view_in_ar_rounded, _threeD ? '2D' : '3D', _toggle3D),
                const SizedBox(width: 8),
                _toolButton(
                  _metric == _Metric.cost ? Icons.currency_rupee_rounded : Icons.how_to_vote_rounded,
                  _metric == _Metric.cost ? 'Height: cost' : 'Height: votes',
                  () => setState(() => _metric = _metric == _Metric.cost ? _Metric.votes : _Metric.cost),
                ),
                const SizedBox(width: 8),
                _toolButton(Icons.center_focus_strong_rounded, 'Fit', _fit),
              ]),
            ]),
          ),
        ),

        if (_loading) const Center(child: CircularProgressIndicator(color: Colors.white)),

        // ---------------- bottom: selected card or summary ----------------
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: SafeArea(
            top: false,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 240),
              transitionBuilder: (c, a) => SlideTransition(
                position: Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(a),
                child: FadeTransition(opacity: a, child: c),
              ),
              child: selected != null
                  ? _SelectedCard(
                      key: ValueKey(selected.id),
                      proposal: selected,
                      ward: _wardName(selected.wardId),
                      votes: _votes[selected.id] ?? 0,
                      onApprove: _resident ? null : () => _approve(selected),
                      onEdit: _resident ? null : () => _edit(selected),
                      onOpen: () => context.push('/proposal/${selected.id}'),
                    )
                  : _Summary(
                      key: const ValueKey('summary'),
                      onBallot: onBallot,
                      pending: pending,
                      asked: asked,
                      metric: _metric,
                    ),
            ),
          ),
        ),
      ]),
    );
  }

  /// Upright 3D pillars + floating labels, depth-sorted (far first).
  List<Widget> _pillars(List<Proposal> visible, Matrix4 full, Size size, double t) {
    final camera = _map.camera;
    final maxMetric = visible.fold<double>(1, (m, p) => math.max(m, _metricOf(p)));
    final items = <({Proposal p, Offset base, double k})>[];
    for (final p in visible) {
      final g = camera.latLngToScreenOffset(LatLng(p.lat!, p.lng!));
      final base = MatrixUtils.transformPoint(full, g);
      final side = MatrixUtils.transformPoint(full, g + const Offset(40, 0));
      final k = ((side - base).distance / 40).clamp(0.3, 1.15);
      if (base.dx < -60 || base.dx > size.width + 60 || base.dy < 250 || base.dy > size.height + 40) continue;
      items.add((p: p, base: base, k: k));
    }
    items.sort((a, b) => a.base.dy.compareTo(b.base.dy));

    final widgets = <Widget>[
      // All prisms in one painter (cheap), labels as widgets (crisp text + taps).
      IgnorePointer(
        child: CustomPaint(
          size: size,
          painter: _PillarPainter([
            for (final it in items)
              _PillarSpec(
                base: it.base,
                width: 16 * it.k,
                height: (14 + 110 * _metricOf(it.p) / maxMetric) * it.k * (0.35 + 0.65 * t),
                color: pinColor(it.p),
                selected: it.p.id == _selectedId,
              ),
          ]),
        ),
      ),
    ];
    // Label collision avoidance: nearest pillars (bottom of screen) claim space
    // first; a label that would overlap one already placed is hidden.
    double heightOf(Proposal p, double k) => (14 + 110 * _metricOf(p) / maxMetric) * k * (0.35 + 0.65 * t);
    double scaleOf(double k) => (0.72 + 0.28 * k).clamp(0.7, 1.0);
    final placed = <Rect>[];
    final labelled = <String>{};
    final byNearness = [...items]
      ..sort((a, b) => (b.p.id == _selectedId ? 1 : 0).compareTo(a.p.id == _selectedId ? 1 : 0) != 0
          ? (b.p.id == _selectedId ? 1 : -1)
          : b.base.dy.compareTo(a.base.dy));
    for (final it in byNearness) {
      final sc = scaleOf(it.k);
      final h = heightOf(it.p, it.k);
      final rect = Rect.fromCenter(
        center: Offset(it.base.dx, it.base.dy - h - 10 - 34 * sc),
        width: 150 * sc,
        height: 60 * sc,
      );
      if (it.p.id == _selectedId || !placed.any((r) => r.overlaps(rect))) {
        placed.add(rect);
        labelled.add(it.p.id);
      }
    }

    for (final it in items) {
      final h = heightOf(it.p, it.k);
      final sel = it.p.id == _selectedId;
      final showLabel = labelled.contains(it.p.id);
      final labelScale = scaleOf(it.k);
      widgets.add(Positioned(
        left: it.base.dx - 80,
        top: it.base.dy - h - 78 * labelScale - 10,
        width: 160,
        child: GestureDetector(
          onTap: () => setState(() => _selectedId = it.p.id),
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            height: 78 * labelScale + h + 10,
            child: Align(
              alignment: Alignment.topCenter,
              child: showLabel
                  ? Opacity(
                      opacity: sel ? 1 : (0.55 + 0.45 * it.k).clamp(0.55, 1.0),
                      child: Transform.scale(
                        scale: labelScale,
                        alignment: Alignment.bottomCenter,
                        child: _PillarLabel(
                          title: it.p.title,
                          value: _metricLabel(it.p),
                          ward: _wardName(it.p.wardId),
                          color: pinColor(it.p),
                          icon: categoryIcon(it.p.category),
                          selected: sel,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ));
    }
    return widgets;
  }

  Widget _glass(Widget child) => Container(
        decoration: BoxDecoration(
          color: AppColors.forestDark.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 18, offset: const Offset(0, 8))],
        ),
        child: child,
      );

  Widget _chip(String label, bool selected, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Material(
          color: selected ? Colors.white : AppColors.forestDark.withValues(alpha: 0.78),
          shape: StadiumBorder(side: BorderSide(color: Colors.white.withValues(alpha: selected ? 1 : 0.2))),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Text(label,
                  style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 12.5, color: selected ? AppColors.forest : Colors.white)),
            ),
          ),
        ),
      );

  Widget _toolButton(IconData icon, String label, VoidCallback onTap) => Material(
        color: Colors.white,
        shape: const StadiumBorder(),
        elevation: 4,
        shadowColor: Colors.black38,
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 17, color: AppColors.forest),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.forest, fontSize: 12.5)),
            ]),
          ),
        ),
      );
}

// ============================== 3D pillars ==============================

class _PillarSpec {
  const _PillarSpec({
    required this.base,
    required this.width,
    required this.height,
    required this.color,
    required this.selected,
  });

  final Offset base; // ground point (screen)
  final double width;
  final double height;
  final Color color;
  final bool selected;
}

/// Draws each pillar as a lit prism: ground shadow, front face, right side
/// face and top face, like a small 3D bar standing on the map.
class _PillarPainter extends CustomPainter {
  _PillarPainter(this.specs);

  final List<_PillarSpec> specs;

  Color _shade(Color c, double f) => Color.lerp(c, f < 0 ? Colors.black : Colors.white, f.abs())!;

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in specs) {
      final w = s.width, h = s.height, b = s.base;
      final depth = Offset(w * 0.42, -w * 0.30); // isometric depth direction
      final left = b.dx - w / 2, right = b.dx + w / 2, top = b.dy - h;

      // soft ground shadow
      canvas.drawOval(
        Rect.fromCenter(center: b + Offset(depth.dx * 0.6, 2), width: w * 2.2, height: w * 0.8),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.22)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      if (s.selected) {
        canvas.drawOval(
          Rect.fromCenter(center: b + Offset(depth.dx * 0.5, 0), width: w * 3.2, height: w * 1.2),
          Paint()
            ..color = AppColors.leaf.withValues(alpha: 0.55)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
      }

      // right side face
      final sidePath = Path()
        ..moveTo(right, b.dy)
        ..lineTo(right + depth.dx, b.dy + depth.dy)
        ..lineTo(right + depth.dx, top + depth.dy)
        ..lineTo(right, top)
        ..close();
      canvas.drawPath(sidePath, Paint()..color = _shade(s.color, -0.35));

      // front face with a vertical light gradient
      final front = Rect.fromLTRB(left, top, right, b.dy);
      canvas.drawRect(
        front,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_shade(s.color, 0.18), s.color, _shade(s.color, -0.12)],
          ).createShader(front),
      );
      // thin kolam-like band near the top
      canvas.drawRect(
        Rect.fromLTRB(left, top + math.min(8, h * 0.18), right, top + math.min(10, h * 0.22)),
        Paint()..color = Colors.white.withValues(alpha: 0.35),
      );

      // top face
      final topPath = Path()
        ..moveTo(left, top)
        ..lineTo(left + depth.dx, top + depth.dy)
        ..lineTo(right + depth.dx, top + depth.dy)
        ..lineTo(right, top)
        ..close();
      canvas.drawPath(topPath, Paint()..color = _shade(s.color, s.selected ? 0.55 : 0.35));
      if (s.selected) {
        canvas.drawPath(
          topPath,
          Paint()
            ..color = AppColors.leaf
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_PillarPainter old) => true;
}

/// Floating name tag above a pillar.
class _PillarLabel extends StatelessWidget {
  const _PillarLabel({
    required this.title,
    required this.value,
    required this.ward,
    required this.color,
    required this.icon,
    required this.selected,
  });

  final String title;
  final String value;
  final String ward;
  final Color color;
  final IconData icon;
  final bool selected;

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          constraints: const BoxConstraints(maxWidth: 156),
          padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
          decoration: BoxDecoration(
            color: selected ? color : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? AppColors.leaf : color.withValues(alpha: 0.4), width: selected ? 2 : 1),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.28), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: selected ? Colors.white.withValues(alpha: 0.2) : color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(icon, size: 14, color: selected ? Colors.white : color),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11.5, fontWeight: FontWeight.w800, color: selected ? Colors.white : AppColors.ink)),
                Text('$value · $ward',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: selected ? Colors.white.withValues(alpha: 0.85) : AppColors.inkMuted)),
              ]),
            ),
          ]),
        ),
        // little stem from the tag down to the pillar
        Container(width: 2, height: 10, color: selected ? AppColors.leaf : Colors.white.withValues(alpha: 0.9)),
      ]);
}

// ============================== bottom cards ==============================

class _Summary extends StatelessWidget {
  const _Summary({super.key, required this.onBallot, required this.pending, required this.asked, required this.metric});

  final int onBallot;
  final int pending;
  final int asked;
  final _Metric metric;

  @override
  Widget build(BuildContext context) {
    Widget tile(String v, String l, Color c) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(v, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c)),
            Text(l, style: const TextStyle(fontSize: 11.5, color: AppColors.inkMuted)),
          ]),
        );
    return Card(
      elevation: 8,
      shadowColor: Colors.black38,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            tile('$onBallot', 'on the ballot', AppColors.forest),
            tile('$pending', 'ideas to review', const Color(0xFFB27300)),
            tile(inrCompact(asked), 'requested', AppColors.forestDark),
          ]),
          const Divider(height: 18),
          Row(children: [
            const Expanded(child: Align(alignment: Alignment.centerLeft, child: MapLegend(showRejected: true))),
            const SizedBox(width: 8),
            Text(metric == _Metric.cost ? 'Height = cost' : 'Height = votes',
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.inkMuted)),
          ]),
        ]),
      ),
    );
  }
}

class _SelectedCard extends StatelessWidget {
  const _SelectedCard({
    super.key,
    required this.proposal,
    required this.ward,
    required this.votes,
    this.onApprove,
    this.onEdit,
    required this.onOpen,
  });

  final Proposal proposal;
  final String ward;
  final int votes;
  final VoidCallback? onApprove;
  final VoidCallback? onEdit;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final p = proposal;
    final pending = p.status == ProposalStatus.pending;
    final (String status, Color color) = switch (p.status) {
      ProposalStatus.approved => ('On the ballot', AppTheme.success),
      ProposalStatus.pending => ('Idea in review', const Color(0xFF8A5A00)),
      ProposalStatus.rejected => ('Not approved', AppColors.inkMuted),
    };
    return Card(
      elevation: 8,
      shadowColor: Colors.black38,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(12)),
              child: Icon(categoryIcon(p.category), color: AppColors.forest, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.title,
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                Text('$ward · ${p.locationName ?? 'Pinned'}',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.inkMuted, fontSize: 12.5)),
              ]),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Text(inr(p.totalCost), style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.forestDark, fontSize: 16)),
            const SizedBox(width: 10),
            Text('· $votes vote${votes == 1 ? '' : 's'}', style: const TextStyle(color: AppColors.inkMuted)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
              child: Text(p.fromResident ? '$status · resident' : status,
                  style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 11.5)),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            if (onEdit == null)
              Expanded(
                child: FilledButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('View details'),
                ),
              ),
            if (pending && onApprove != null) ...[
              Expanded(
                child: FilledButton.icon(
                  onPressed: onApprove,
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Approve'),
                ),
              ),
              const SizedBox(width: 8),
            ],
            if (onEdit != null)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onEdit,
                  icon: Icon(pending ? Icons.rate_review_outlined : Icons.edit_outlined),
                  label: Text(pending ? 'Review' : 'Edit'),
                ),
              ),
          ]),
        ]),
      ),
    );
  }
}
