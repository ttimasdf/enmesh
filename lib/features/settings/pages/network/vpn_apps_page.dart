import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
import 'package:enmesh/core/services/service_manager.dart';
import 'package:enmesh/core/states/vpn_state.dart';
import 'package:enmesh/core/ui/base_settings_page.dart';
import 'package:enmesh/features/settings/widgets/settings_components.dart';
import 'package:enmesh/generated/locale_keys.g.dart';
import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:vpn_service_plugin/installed_app.dart';

/// Android 分应用 VPN：模式选择 + 应用多选列表
class VpnAppsPage extends BaseSettingsPage {
  const VpnAppsPage({super.key});

  @override
  String get title => LocaleKeys.android_vpn_apps.tr();

  @override
  Widget buildContent(BuildContext context) {
    return const _VpnAppsContent();
  }
}

class _VpnAppsContent extends StatefulWidget {
  const _VpnAppsContent();

  @override
  State<_VpnAppsContent> createState() => _VpnAppsContentState();
}

class _VpnAppsContentState extends State<_VpnAppsContent> {
  List<InstalledApp>? _apps;
  String? _error;
  final _searchController = TextEditingController();
  String _query = '';
  bool _selectedOnly = false;

  @override
  void initState() {
    super.initState();
    _loadApps();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadApps() async {
    setState(() {
      _apps = null;
      _error = null;
    });

    final plugin = ServiceManager().vpn.plugin;
    if (plugin == null) {
      setState(() => _error = 'vpn_unavailable');
      return;
    }

    try {
      final apps = await plugin.getInstalledApps();
      if (!mounted) return;
      setState(() => _apps = apps);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  Future<void> _togglePackage(String packageName, bool selected) async {
    final services = ServiceManager();
    final current = List<String>.from(services.vpnState.androidVpnApps.value);
    if (selected) {
      if (!current.contains(packageName)) current.add(packageName);
    } else {
      current.removeWhere((package) => package == packageName);
    }
    await services.appSettings.setAndroidVpnApps(current);
  }

  List<InstalledApp> _filteredApps(List<InstalledApp> apps, Set<String> selected) {
    final query = _query.trim().toLowerCase();
    return apps.where((app) {
      if (_selectedOnly && !selected.contains(app.packageName)) return false;
      if (query.isEmpty) return true;
      return app.label.toLowerCase().contains(query) ||
          app.packageName.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final services = ServiceManager();

    return Watch((context) {
      final mode = services.vpnState.androidVpnAppMode.watch(context);
      final selected =
          services.vpnState.androidVpnApps.watch(context).toSet();
      final apps = _apps;
      final error = _error;

      final header = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsSegmentedChoice<AndroidVpnAppMode>(
            title: LocaleKeys.android_vpn_app_mode.tr(),
            description: switch (mode) {
              AndroidVpnAppMode.disabled =>
                LocaleKeys.android_vpn_app_mode_all_desc.tr(),
              AndroidVpnAppMode.denylist =>
                LocaleKeys.android_vpn_app_mode_denylist_desc.tr(),
              AndroidVpnAppMode.allowlist =>
                LocaleKeys.android_vpn_app_mode_allowlist_desc.tr(),
            },
            value: mode,
            segments: [
              ButtonSegment(
                value: AndroidVpnAppMode.disabled,
                label: Text(LocaleKeys.android_vpn_app_mode_all.tr()),
              ),
              ButtonSegment(
                value: AndroidVpnAppMode.denylist,
                label: Text(LocaleKeys.android_vpn_app_mode_denylist.tr()),
              ),
              ButtonSegment(
                value: AndroidVpnAppMode.allowlist,
                label: Text(LocaleKeys.android_vpn_app_mode_allowlist.tr()),
              ),
            ],
            onChanged: services.appSettings.setAndroidVpnAppMode,
          ),
          if (mode == AndroidVpnAppMode.disabled)
            SettingsNotice(
              icon: Icons.info_outline,
              message: LocaleKeys.android_vpn_apps_disabled_notice.tr(),
            ),
          if (mode == AndroidVpnAppMode.allowlist && selected.isEmpty)
            SettingsNotice(
              icon: Icons.warning_amber_rounded,
              message: LocaleKeys.android_vpn_apps_empty_allowlist_notice.tr(),
            ),
          if (mode != AndroidVpnAppMode.disabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 0),
              child: Text(
                mode == AndroidVpnAppMode.denylist
                    ? LocaleKeys.android_vpn_apps_list_caption_denylist.tr()
                    : LocaleKeys.android_vpn_apps_list_caption_allowlist.tr(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: LocaleKeys.android_vpn_apps_search_hint.tr(),
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: Text(
                    LocaleKeys.android_vpn_apps_selected_only.tr(
                      namedArgs: {'count': selected.length.toString()},
                    ),
                  ),
                  selected: _selectedOnly,
                  onSelected: (value) =>
                      setState(() => _selectedOnly = value),
                ),
              ],
            ),
          ),
        ],
      );

      final Widget body;
      if (error != null) {
        body = Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 12),
              Text(LocaleKeys.android_vpn_apps_load_failed.tr()),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: _loadApps,
                icon: const Icon(Icons.refresh),
                label: Text(LocaleKeys.retry.tr()),
              ),
            ],
          ),
        );
      } else if (apps == null) {
        body = Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
              Text(LocaleKeys.loading.tr()),
            ],
          ),
        );
      } else {
        final visible = _filteredApps(apps, selected);
        body = visible.isEmpty
            ? Center(child: Text(LocaleKeys.android_vpn_apps_no_match.tr()))
            : ListView.builder(
                padding: const EdgeInsets.only(bottom: 16),
                itemCount: visible.length,
                itemBuilder: (context, index) {
                  final app = visible[index];
                  final isSelected = selected.contains(app.packageName);
                  return CheckboxListTile(
                    value: isSelected,
                    onChanged: (value) =>
                        _togglePackage(app.packageName, value ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18),
                    title: Text(app.label),
                    subtitle: Text(
                      app.packageName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    secondary: _AppIcon(icon: app.icon),
                  );
                },
              );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: 4),
          Expanded(child: body),
        ],
      );
    });
  }
}

class _AppIcon extends StatelessWidget {
  final Uint8List? icon;

  const _AppIcon({this.icon});

  @override
  Widget build(BuildContext context) {
    if (icon == null) {
      return Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.android, size: 20),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.memory(
        icon!,
        width: 36,
        height: 36,
        gaplessPlayback: true,
        errorBuilder:
            (_, _, _) => const SizedBox(width: 36, height: 36),
      ),
    );
  }
}
