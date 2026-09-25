import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/proposal.dart';
import '../providers/auth_provider.dart';
import '../providers/ward_provider.dart';
import '../theme.dart';
import '../utils/categories.dart';
import '../utils/format.dart';
import '../widgets/ballot_widgets.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';
import '../widgets/map_widgets.dart';
import 'proposal_form_screen.dart';

enum _MapFilter { all, ballot, ideas }

/// Map tab: every project on the ballot and every idea as a pin.
/// Residents see their ward (approved projects + their own ideas);
/// admins can switch to all wards to review ideas by place.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key, this.focusId});

  final String? focusId; // /map?focus=<proposal id> opens with that pin selected

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  _MapFilter _filter = _MapFilter.all;
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.focusId;
  }

  @override
  void didUpdateWidget(MapScreen old) {
    super.didUpdateWidget(old);
    if (widget.focusId != old.focusId && widget.focusId != null) setState(() => _selectedId = widget.focusId);
  }

  List<Proposal> _source(WardProvider wp) {
    final byId = <String, Proposal>{for (final p in wp.proposals) p.id: p};
    for (final i in wp.myIdeas) {
      byId.putIfAbsent(i.id, () => i);
    }
    return byId.values.toList();
  }

  bool _passes(Proposal p) => switch (_filter) {
        _MapFilter.all => true,
        _MapFilter.ballot => p.isApproved,
        _MapFilter.ideas => p.fromResident && !p.isApproved,
      };

  @override
  Widget build(BuildContext context) {
    final wp = context.watch<WardProvider>();
    final isAdmin = context.watch<AuthProvider>().profile?.isAdmin ?? false;
    final all = _source(wp).where(_passes).toList();
    final pinned = all.where((p) => p.hasLocation).toList();
    final unpinned = all.length - pinned.length;
    final selected = pinned.where((p) => p.id == _selectedId).firstOrNull;

    final points = [for (final p in pinned) proposalPoint(p)!];
    final center = selected != null
        ? proposalPoint(selected)!
        : (points.length == 1 ? points.first : wardCenter(wp.ward));

    return Scaffold(
      body: Column(children: [
        BrandHeader(
          title: 'Ward map',
          subtitle: '${wp.ward?.name ?? ''} · ${pinned.length} pins',
          bottomPadding: 14,
          actions: [
            HeaderIconButton(
              icon: Icons.view_in_ar_rounded,
              tooltip: isAdmin ? '3D map of all wards' : '3D ward map',
              onPressed: () => context.push(isAdmin ? '/admin/map' : '/map3d'),
            ),
          ],
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final (f, label, icon) in [
                (_MapFilter.all, 'Everything', Icons.layers_rounded),
                (_MapFilter.ballot, 'On the ballot', Icons.how_to_vote_rounded),
                (_MapFilter.ideas, 'Ideas in review', Icons.lightbulb_outline_rounded),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _HeaderChip(
                    label: label,
                    icon: icon,
                    selected: _filter == f,
                    onTap: () => setState(() {
                      _filter = f;
                      _selectedId = null;
                    }),
                  ),
                ),
            ]),
          ),
        ),
        Expanded(
          child: Stack(children: [
            FlutterMap(
              // Rebuild (and re-fit) when the set of pins changes.
              key: ValueKey('${_filter.name}-${pinned.length}-${wp.ward?.id}'),
              options: MapOptions(
                backgroundColor: kMapBackground,
                initialCenter: center,
                initialZoom: 14.5,
                initialCameraFit: selected == null && points.length > 1
                    ? CameraFit.coordinates(coordinates: points, padding: const EdgeInsets.fromLTRB(50, 70, 50, 200), maxZoom: 16)
                    : null,
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                onTap: (_, _) => setState(() => _selectedId = null),
              ),
              children: [
                ...osmLayers(),
                MarkerLayer(markers: [
                  // Selected pin last so it draws on top.
                  for (final p in [...pinned.where((p) => p.id != _selectedId), ?selected])
                    proposalMarker(
                      p,
                      selected: p.id == _selectedId,
                      onBallot: wp.isOnMyBallot(p.id) || wp.isPicked(p.id),
                      onTap: () => setState(() => _selectedId = p.id),
                    ),
                ]),
                osmAttribution,
              ],
            ),
            Positioned(left: 12, top: 12, right: 12, child: Align(alignment: Alignment.topLeft, child: MapLegend(showRejected: isAdmin))),
            if (all.isEmpty)
              const Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Nothing to show for this filter yet.'),
                  ),
                ),
              ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 30, // above the OSM credit line
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (c, a) => SlideTransition(
                  position: Tween(begin: const Offset(0, 0.3), end: Offset.zero).animate(a),
                  child: FadeTransition(opacity: a, child: c),
                ),
                child: selected != null
                    ? _PinCard(key: ValueKey(selected.id), proposal: selected, isAdmin: isAdmin, onChanged: wp.load)
                    : unpinned > 0
                        ? _NoteCard(
                            key: const ValueKey('note'),
                            text: '$unpinned ${unpinned == 1 ? 'project has' : 'projects have'} no location yet'
                                '${isAdmin ? '. Edit a proposal to drop its pin.' : '.'}',
                          )
                        : const SizedBox.shrink(),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _HeaderChip extends StatelessWidget {
  const _HeaderChip({required this.label, required this.icon, required this.selected, required this.onTap});

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: selected ? Colors.white : Colors.white.withValues(alpha: 0.12),
        shape: StadiumBorder(side: BorderSide(color: Colors.white.withValues(alpha: selected ? 1 : 0.25))),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 16, color: selected ? AppColors.forest : Colors.white),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w700, color: selected ? AppColors.forest : Colors.white)),
            ]),
          ),
        ),
      );
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => MessageBanner(text, isError: false);
}

/// Bottom card for the selected pin.
class _PinCard extends StatelessWidget {
  const _PinCard({super.key, required this.proposal, required this.isAdmin, required this.onChanged});

  final Proposal proposal;
  final bool isAdmin;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final wp = context.watch<WardProvider>();
    final p = proposal;
    final inMyWard = wp.byId(p.id) != null; // approved + in my ward → detail page works
    final (String status, Color color) = switch (p.status) {
      ProposalStatus.approved => ('On the ballot', AppTheme.success),
      ProposalStatus.pending => ('Idea in review', const Color(0xFF8A5A00)),
      ProposalStatus.rejected => ('Not approved', AppColors.inkMuted),
    };

    Future<void> edit() async {
      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => ProposalFormScreen(mode: ProposalFormMode.edit, proposal: p)),
      );
      if (saved == true) onChanged();
    }

    return Card(
      elevation: 6,
      shadowColor: Colors.black26,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: AppColors.mint, borderRadius: BorderRadius.circular(12)),
              child: Icon(categoryIcon(p.category), color: AppColors.forest, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                const SizedBox(height: 2),
                Row(children: [
                  const Icon(Icons.place_outlined, size: 14, color: AppColors.inkMuted),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(p.locationName ?? 'Pinned location',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.inkMuted, fontSize: 12.5)),
                  ),
                ]),
              ]),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Text(inr(p.totalCost), style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.forestDark, fontSize: 16)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
              child: Text(p.fromResident ? '$status · resident idea' : status,
                  style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 11.5)),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            if (inMyWard && wp.canVote) ...[
              Expanded(
                child: wp.isPicked(p.id)
                    ? OutlinedButton.icon(
                        onPressed: () => togglePickWithFeedback(context, p),
                        icon: const Icon(Icons.check_rounded),
                        label: const Text('On ballot'),
                      )
                    : FilledButton.icon(
                        onPressed: () => togglePickWithFeedback(context, p),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Add to ballot'),
                      ),
              ),
              const SizedBox(width: 8),
            ],
            if (inMyWard)
              Expanded(
                child: OutlinedButton(
                  onPressed: () => context.push('/proposal/${p.id}'),
                  child: const Text('View details'),
                ),
              )
            else if (isAdmin)
              Expanded(
                child: FilledButton.icon(
                  onPressed: edit,
                  icon: Icon(p.status == ProposalStatus.pending ? Icons.rate_review_outlined : Icons.edit_outlined),
                  label: Text(p.status == ProposalStatus.pending ? 'Review idea' : 'Edit'),
                ),
              )
            else
              Expanded(
                child: OutlinedButton(onPressed: () => context.push('/ideas'), child: const Text('My ideas')),
              ),
          ]),
        ]),
      ),
    );
  }
}
