import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../push/push_service.dart';
import '../settings/app_settings.dart';
import '../widgets/links.dart';
import 'road_data.dart';
import 'roads_repository.dart';
import 'roads_widgets.dart';

/// The Roads screen (roads spec D12): Route 101 and Highway 63, each with
/// closures and incidents, conditions and roadwork (and Highway 63's
/// cameras), then the Town's work, then sources. Opened from More, from
/// Today's road card and from a road notification.
class RoadsScreen extends StatelessWidget {
  const RoadsScreen({
    super.key,
    required this.settings,
    required this.repository,
    required this.push,
    this.cameraImage = networkCameraImage,
    this.now,
  });

  final AppSettings settings;
  final RoadsRepository repository;

  /// For the "Get notified" switch (spec D9; phones only).
  final PushService push;
  final CameraImageFor cameraImage;

  /// For tests; defaults to the current time.
  final DateTime? now;

  Future<void> _setNotified(BuildContext context, bool on) async {
    if (!on) return settings.setRoadClosures(false);
    final messenger = ScaffoldMessenger.of(context);
    final denied = AppLocalizations.of(context).settingsPermissionDenied;
    if (await push.requestPermission()) {
      await settings.setRoadClosures(true);
    } else {
      messenger.showSnackBar(SnackBar(content: Text(denied)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.roadsTitle)),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([repository, settings]),
          builder: (context, _) {
            final at = now ?? DateTime.now();
            final language = settings.language ?? AppLanguage.fr;
            if (repository.loading && repository.items.isEmpty) return const Center(child: CircularProgressIndicator());
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (push.isSupported) ...[
                  Card(
                    margin: EdgeInsets.zero,
                    child: SwitchListTile(
                      secondary: const Icon(Icons.notifications_active_outlined),
                      title: Text(l10n.roadsNotifyTitle),
                      subtitle: Text(l10n.roadsNotifySubtitle),
                      value: settings.roadClosuresEnabled,
                      onChanged: (on) => _setNotified(context, on),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
                for (final road in Road.values) ...[
                  _RoadSection(road: road, repository: repository, language: language, now: at, cameraImage: cameraImage),
                  const SizedBox(height: 32),
                ],
                _TownSection(repository: repository, language: language, now: at),
                const SizedBox(height: 32),
                ..._sources(context, language),
              ],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _sources(BuildContext context, AppLanguage language) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final fr = language == AppLanguage.fr;
    final muted = textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return [
      _Heading(l10n.roadsSourcesHeading),
      Text(l10n.roadsRelayNote, style: textTheme.bodyLarge),
      const SizedBox(height: 8),
      _Link(l10n.roadsQuebec511Link, fr ? RoadLinks.quebec511Fr : RoadLinks.quebec511En),
      _Link(l10n.roadsOntario511Link, fr ? RoadLinks.ontario511Fr : RoadLinks.ontario511En),
      _Link(l10n.roadsTownLink, fr ? RoadLinks.townFr : RoadLinks.townEn),
      const SizedBox(height: 8),
      Text(l10n.roadsQuebecSource, style: muted),
      const SizedBox(height: 4),
      Text(l10n.roadsOntarioSource, style: muted),
      const SizedBox(height: 4),
      Text(l10n.roadsTownSource, style: muted),
    ];
  }
}

void _openItem(BuildContext context, RoadItem item, AppLanguage language) => Navigator.of(context).push(
  MaterialPageRoute<void>(builder: (_) => RoadItemScreen(item: item, language: language)),
);

class _Heading extends StatelessWidget {
  const _Heading(this.text, {this.small = false});

  final String text;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(bottom: 8, top: small ? 12 : 0),
      child: Semantics(header: true, child: Text(text, style: small ? textTheme.titleMedium : textTheme.titleLarge)),
    );
  }
}

class _Link extends StatelessWidget {
  const _Link(this.label, this.url);

  final String label;
  final String url;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: TextButton.icon(
      icon: const Icon(Icons.open_in_new),
      label: Text(label),
      onPressed: () => openLink(Uri.parse(url)),
    ),
  );
}

/// One road: health, closures and incidents, conditions, roadwork, cameras.
class _RoadSection extends StatelessWidget {
  const _RoadSection({
    required this.road,
    required this.repository,
    required this.language,
    required this.now,
    required this.cameraImage,
  });

  final Road road;
  final RoadsRepository repository;
  final AppLanguage language;
  final DateTime now;
  final CameraImageFor cameraImage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final items = repository.itemsFor(road);
    final urgent = [for (final i in items) if (i.kind == RoadItemKind.closure || i.kind == RoadItemKind.incident) i];
    final work = [for (final i in items) if (i.kind == RoadItemKind.roadwork) i];
    final health = roadsHealthLine(context, repository, road.sources, now);
    // "Nothing reported" is a claim: only after a recent check of the item sources.
    final itemSources = road.sources.where((s) => !s.endsWith('conditions')).toList();
    final itemsChecked = repository.health(itemSources, now) is CheckedRecently;
    final conditions = repository.conditions(road);
    final cameras = road == Road.highway63 ? repository.cameras : const <RoadCamera>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Heading(roadHeading(l10n, road)),
        if (health != null) RoadsHealthLine(health: health),
        const SizedBox(height: 8),
        if (urgent.isNotEmpty) ...[
          _Heading(l10n.roadsClosuresHeading, small: true),
          for (final item in urgent)
            RoadItemCard(item: item, language: language, now: now, onTap: () => _openItem(context, item, language)),
        ] else if (work.isEmpty && itemsChecked)
          Row(
            children: [
              const Icon(Icons.check_circle_outline, size: 24),
              const SizedBox(width: 8),
              Expanded(child: Text(l10n.roadsNothingReported, style: textTheme.bodyLarge)),
            ],
          ),
        if (conditions != null) ...[
          _Heading(l10n.roadsConditionsHeading, small: true),
          if (conditions.segments.isEmpty && conditions.inSeason == false)
            Text(l10n.roadsConditionsOffSeason, style: textTheme.bodyLarge)
          else
            for (final s in conditions.segments) SegmentConditions(segment: s, language: language),
        ],
        if (work.isNotEmpty) ...[
          _Heading(l10n.roadsRoadworkHeading, small: true),
          for (final item in work)
            RoadItemCard(item: item, language: language, now: now, onTap: () => _openItem(context, item, language)),
        ],
        if (cameras.isNotEmpty) ...[
          _Heading(l10n.roadsCamerasHeading, small: true),
          for (final camera in cameras)
            for (final view in camera.views)
              CameraViewTile(camera: camera, view: view, language: language, imageFor: cameraImage),
          Text(
            l10n.roadsCameraCredit,
            style: textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

/// The Town's Work Info items.
class _TownSection extends StatelessWidget {
  const _TownSection({required this.repository, required this.language, required this.now});

  final RoadsRepository repository;
  final AppLanguage language;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final items = repository.itemsFor(null);
    final health = roadsHealthLine(context, repository, townSources, now);
    final checked = repository.health(townSources, now) is CheckedRecently;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Heading(l10n.roadsTownWorkHeading),
        Text(l10n.roadsTownWorkNote, style: textTheme.bodyLarge),
        const SizedBox(height: 8),
        if (health != null) ...[RoadsHealthLine(health: health), const SizedBox(height: 8)],
        for (final item in items)
          RoadItemCard(item: item, language: language, now: now, onTap: () => _openItem(context, item, language)),
        if (items.isEmpty && checked) Text(l10n.roadsNoTownWork, style: textTheme.bodyLarge),
      ],
    );
  }
}

/// One item: headline, status, the source's own text, and a link to it.
class RoadItemScreen extends StatelessWidget {
  const RoadItemScreen({super.key, required this.item, required this.language, this.now});

  final RoadItem item;
  final AppLanguage language;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final at = now ?? DateTime.now();
    final shownIn = item.displayLanguage(language);
    final status = itemStatus(context, item, at);
    final body = item.body(language);
    final url = item.sourceUrl(language);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.roadsTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (shownIn != language) ...[
              Row(
                children: [
                  const Icon(Icons.translate),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      shownIn == AppLanguage.fr ? l10n.alertOnlyFrench : l10n.alertOnlyEnglish,
                      style: textTheme.bodyLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            if (item.road != null) Text(roadName(l10n, item.road!), style: textTheme.labelLarge),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(roadItemIcon(item.kind), size: 28),
                const SizedBox(width: 8),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(itemHeadline(l10n, item, language), style: textTheme.headlineSmall),
                  ),
                ),
              ],
            ),
            if (status != null) ...[const SizedBox(height: 8), Text(status, style: textTheme.titleMedium)],
            if (item.kind != RoadItemKind.town && item.endsAt != null) ...[
              const SizedBox(height: 4),
              Text(l10n.roadsExpectedEnd(roadWhen(context, item.endsAt!)), style: textTheme.bodyLarge),
            ],
            if (body.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(body, locale: shownIn.locale, style: textTheme.bodyLarge),
            ],
            if (url.isNotEmpty) ...[
              const SizedBox(height: 16),
              _Link(l10n.roadsOpenSource, url),
            ],
          ],
        ),
      ),
    );
  }
}
