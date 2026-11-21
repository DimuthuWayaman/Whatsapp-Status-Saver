import 'package:flutter/material.dart';

import '../services/status_service.dart';
import '../widgets/app_logo.dart';
import '../widgets/status_grid.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.service});

  final StatusService service;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  StatusService get service => widget.service;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Coming back from WhatsApp → pick up newly viewed statuses.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !service.loading) service.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: theme.scaffoldBackgroundColor,
          surfaceTintColor: Colors.transparent,
          titleSpacing: 16,
          title: Row(
            children: [
              const AppLogo(size: 36),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Status Saver', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                  ListenableBuilder(
                    listenable: service,
                    builder: (context, _) => Text(
                      service.app.label,
                      style: theme.textTheme.labelMedium?.copyWith(color: scheme.primary),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            ListenableBuilder(
              listenable: service,
              builder: (context, _) => PopupMenuButton<WaApp>(
                tooltip: 'Switch app',
                icon: const Icon(Icons.swap_horiz_rounded),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                initialValue: service.app,
                onSelected: service.switchApp,
                itemBuilder: (_) => [
                  for (final a in WaApp.values)
                    PopupMenuItem(
                      value: a,
                      child: Row(children: [
                        Icon(
                          a == service.app ? Icons.radio_button_checked : Icons.radio_button_off,
                          color: scheme.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Text(a == WaApp.whatsapp ? 'WhatsApp' : 'WhatsApp Business'),
                      ]),
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: service.refresh,
            ),
            const SizedBox(width: 4),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(60),
            child: ListenableBuilder(
              listenable: service,
              builder: (context, _) => Container(
                height: 46,
                margin: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TabBar(
                  dividerColor: Colors.transparent,
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicator: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  labelColor: scheme.onPrimary,
                  unselectedLabelColor: scheme.onSurfaceVariant,
                  labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  splashBorderRadius: BorderRadius.circular(20),
                  tabs: [
                    _tab('Images', service.images.length),
                    _tab('Videos', service.videos.length),
                    _tab('Saved', service.saved.length),
                  ],
                ),
              ),
            ),
          ),
        ),
        body: ListenableBuilder(
          listenable: service,
          builder: (context, _) {
            final needsAccess = !service.hasPermission;
            if (service.loading && service.statuses.isEmpty && service.saved.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            Widget statusTab(Widget grid) => needsAccess ? _AccessCard(service: service) : grid;
            return TabBarView(
              children: [
                statusTab(StatusGrid(
                  service: service,
                  items: service.images,
                  emptyIcon: Icons.photo_library_outlined,
                  emptyTitle: 'No image statuses yet',
                  emptyText: 'Open ${service.app.label} and view some statuses, then come back here.',
                )),
                statusTab(StatusGrid(
                  service: service,
                  items: service.videos,
                  emptyIcon: Icons.video_library_outlined,
                  emptyTitle: 'No video statuses yet',
                  emptyText: 'Open ${service.app.label} and watch some statuses, then come back here.',
                )),
                StatusGrid(
                  service: service,
                  items: service.saved,
                  savedMode: true,
                  emptyIcon: Icons.download_done_rounded,
                  emptyTitle: 'Nothing saved yet',
                  emptyText: 'Tap the download button on any status to keep it in your gallery.',
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Tab _tab(String label, int count) => Tab(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Text('$count', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
            ],
          ],
        ),
      );
}

class _AccessCard extends StatelessWidget {
  const _AccessCard({required this.service});

  final StatusService service;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (!service.installed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.error_outline_rounded, size: 56, color: scheme.error),
            const SizedBox(height: 16),
            Text('${service.app.label} is not installed',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text('Install it, or switch app using the ⇄ button above.',
                textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
          ]),
        ),
      );
    }

    Widget step(int n, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            CircleAvatar(
              radius: 13,
              backgroundColor: scheme.primaryContainer,
              child: Text('$n',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onPrimaryContainer)),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
          ]),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      children: [
        Card(
          elevation: 0,
          color: scheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const AppLogo(size: 88),
                const SizedBox(height: 20),
                Text('Allow access to statuses',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(
                  'Status Saver needs one-time access to the ${service.app.label} status folder to show the statuses you have viewed.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 20),
                step(1, 'Tap "Grant access" below'),
                step(2, 'Tap "Use this folder" at the bottom'),
                step(3, 'Tap "Allow" to confirm'),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    icon: const Icon(Icons.folder_open_rounded),
                    label: const Text('Grant access', style: TextStyle(fontWeight: FontWeight.w600)),
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final ok = await service.requestPermission();
                      if (!ok) {
                        messenger.showSnackBar(const SnackBar(
                          content: Text('Please select the ".Statuses" folder and tap "Use this folder".'),
                        ));
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
