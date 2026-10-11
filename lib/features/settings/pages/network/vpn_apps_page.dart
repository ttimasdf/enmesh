import 'package:easy_localization/easy_localization.dart';
import 'package:enmesh/core/services/service_manager.dart';
import 'package:enmesh/core/states/vpn_state.dart';
import 'package:enmesh/core/ui/base_settings_page.dart';
import 'package:enmesh/features/settings/widgets/settings_components.dart';
import 'package:enmesh/generated/locale_keys.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  Future<void> _setSelection(Set<String> selection) async {
    await ServiceManager().appSettings.setAndroidVpnApps(selection.toList());
  }

  Future<void> _togglePackage(String packageName, bool selected) async {
    final current = Set<String>.from(
      ServiceManager().vpnState.androidVpnApps.value,
    );
    if (selected) {
      current.add(packageName);
    } else {
      current.remove(packageName);
    }
    await _setSelection(current);
  }

  void _selectAll(Set<String> visible, Set<String> selected) {
    _setSelection({...selected, ...visible});
  }

  void _selectNone(Set<String> visible, Set<String> selected) {
    _setSelection(selected.difference(visible));
  }

  void _selectInvert(Set<String> visible, Set<String> selected) {
    final next = Set<String>.from(selected);
    for (final package in visible) {
      if (next.contains(package)) {
        next.remove(package);
      } else {
        next.add(package);
      }
    }
    _setSelection(next);
  }

  Future<void> _importFromClipboard(List<InstalledApp> apps) async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text ?? '';
    final known = text
        .split(RegExp(r'[\s,;]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .where((package) => apps.any((app) => app.packageName == package))
        .toSet();

    if (known.isEmpty) {
      _showSnackbar(LocaleKeys.android_vpn_apps_import_none.tr());
      return;
    }

    await _setSelection(known);
    _showSnackbar(
      LocaleKeys.android_vpn_apps_import_done.tr(
        namedArgs: {'count': known.length.toString()},
      ),
    );
  }

  Future<void> _exportToClipboard(List<InstalledApp> apps) async {
    final selected = ServiceManager().vpnState.androidVpnApps.value.toSet();
    final byPackage = {for (final app in apps) app.packageName: app.label};
    final packages = selected.toList()
      ..sort((a, b) => (byPackage[a] ?? a).compareTo(byPackage[b] ?? b));
    await Clipboard.setData(ClipboardData(text: packages.join('\n')));
    _showSnackbar(
      LocaleKeys.android_vpn_apps_export_done.tr(
        namedArgs: {'count': packages.length.toString()},
      ),
    );
  }

  void _showSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  List<InstalledApp> _visibleApps(
    List<InstalledApp> apps,
    Set<String> selected,
    bool showSystem,
    bool selectedOnly,
    AndroidVpnAppsSort sort,
    bool reverse,
  ) {
    final query = _query.trim().toLowerCase();
    Iterable<InstalledApp> visible = apps.where((app) {
      if (!showSystem && app.system) return false;
      if (selectedOnly && !selected.contains(app.packageName)) return false;
      if (query.isEmpty) return true;
      return app.label.toLowerCase().contains(query) ||
          app.packageName.toLowerCase().contains(query);
    });

    int compare(InstalledApp a, InstalledApp b) {
      switch (sort) {
        case AndroidVpnAppsSort.name:
          return a.label.toLowerCase().compareTo(b.label.toLowerCase());
        case AndroidVpnAppsSort.packageName:
          return a.packageName.compareTo(b.packageName);
        case AndroidVpnAppsSort.installTime:
          return a.installTime.compareTo(b.installTime);
        case AndroidVpnAppsSort.updateTime:
          return a.updateTime.compareTo(b.updateTime);
      }
    }

    var list = visible.toList()..sort(compare);
    if (reverse) list = list.reversed.toList();
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final services = ServiceManager();

    return Watch((context) {
      final mode = services.vpnState.androidVpnAppMode.watch(context);
      final selected = services.vpnState.androidVpnApps.watch(context).toSet();
      final showSystem = services.vpnState.androidVpnAppsShowSystem.watch(
        context,
      );
      final selectedOnly = services.vpnState.androidVpnAppsSelectedOnly.watch(
        context,
      );
      final sort = services.vpnState.androidVpnAppsSort.watch(context);
      final reverse = services.vpnState.androidVpnAppsReverse.watch(context);
      final apps = _apps;
      final error = _error;
      final visible =
          apps == null
              ? const <InstalledApp>[]
              : _visibleApps(
                  apps,
                  selected,
                  showSystem,
                  selectedOnly,
                  sort,
                  reverse,
                );

      Widget buildListTile(InstalledApp app, bool isSelected) {
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
      }

      final Widget bodySliver;
      if (error != null) {
        bodySliver = SliverFillRemaining(
          child: Center(
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
          ),
        );
      } else if (apps == null) {
        bodySliver = SliverFillRemaining(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 12),
                Text(LocaleKeys.loading.tr()),
              ],
            ),
          ),
        );
      } else if (visible.isEmpty) {
        bodySliver = SliverFillRemaining(
          child: Center(child: Text(LocaleKeys.android_vpn_apps_no_match.tr())),
        );
      } else {
        bodySliver = SliverList.builder(
          itemCount: visible.length,
          itemBuilder: (context, index) => buildListTile(
            visible[index],
            selected.contains(visible[index].packageName),
          ),
        );
      }

      // 随内容滚动的头部：模式切换与提示
      final scrollableHeader = Column(
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
        ],
      );

      // 固定在顶部的搜索行（随字号自适应高度）
      final searchBarHeight =
          (MediaQuery.textScalerOf(context).scale(48) + 12).clamp(
            60.0,
            88.0,
          );
      final searchBar = Material(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Padding(
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
              _AppsMenuButton(
                visiblePackages: visible.map((app) => app.packageName).toSet(),
                apps: apps ?? const [],
              ),
            ],
          ),
        ),
      );

      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: scrollableHeader),
          SliverPersistentHeader(
            pinned: true,
            delegate: _PinnedBarDelegate(
              extent: searchBarHeight,
              bar: searchBar,
            ),
          ),
          bodySliver,
        ],
      );
    });
  }
}

class _PinnedBarDelegate extends SliverPersistentHeaderDelegate {
  final double extent;
  final Widget bar;

  _PinnedBarDelegate({required this.extent, required this.bar});

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => bar;

  @override
  double get minExtent => extent;

  @override
  double get maxExtent => extent;

  @override
  bool shouldRebuild(_PinnedBarDelegate oldDelegate) =>
      extent != oldDelegate.extent || bar != oldDelegate.bar;
}

/// 搜索栏旁的过滤/批量操作菜单（参照 Clash 的 AccessControlMenu）。
class _AppsMenuButton extends StatelessWidget {
  final Set<String> visiblePackages;
  final List<InstalledApp> apps;

  const _AppsMenuButton({required this.visiblePackages, required this.apps});

  @override
  Widget build(BuildContext context) {
    final services = ServiceManager();

    return PopupMenuButton<String>(
      icon: const Icon(Icons.filter_list),
      tooltip: LocaleKeys.android_vpn_apps_menu_filter.tr(),
      onSelected: (action) => _onSelected(context, action, services),
      itemBuilder: (context) {
        final showSystem = services.vpnState.androidVpnAppsShowSystem.watch(
          context,
        );
        final selectedOnly = services.vpnState.androidVpnAppsSelectedOnly.watch(
          context,
        );
        final sort = services.vpnState.androidVpnAppsSort.watch(context);
        final reverse = services.vpnState.androidVpnAppsReverse.watch(context);
        return [
          PopupMenuItem(
            value: 'select_all',
            child: Text(LocaleKeys.android_vpn_apps_select_all.tr()),
          ),
          PopupMenuItem(
            value: 'select_none',
            child: Text(LocaleKeys.android_vpn_apps_select_none.tr()),
          ),
          PopupMenuItem(
            value: 'select_invert',
            child: Text(LocaleKeys.android_vpn_apps_select_invert.tr()),
          ),
          const PopupMenuDivider(),
          _menuHeader(context, LocaleKeys.android_vpn_apps_menu_filter.tr()),
          CheckedPopupMenuItem(
            value: 'show_system',
            checked: showSystem,
            child: Text(LocaleKeys.android_vpn_apps_show_system.tr()),
          ),
          CheckedPopupMenuItem(
            value: 'selected_only',
            checked: selectedOnly,
            child: Text(LocaleKeys.android_vpn_apps_selected_only.tr()),
          ),
          const PopupMenuDivider(),
          _menuHeader(context, LocaleKeys.android_vpn_apps_menu_sort.tr()),
          CheckedPopupMenuItem(
            value: 'sort_name',
            checked: sort == AndroidVpnAppsSort.name,
            child: Text(LocaleKeys.android_vpn_apps_sort_name.tr()),
          ),
          CheckedPopupMenuItem(
            value: 'sort_package',
            checked: sort == AndroidVpnAppsSort.packageName,
            child: Text(LocaleKeys.android_vpn_apps_sort_package.tr()),
          ),
          CheckedPopupMenuItem(
            value: 'sort_install_time',
            checked: sort == AndroidVpnAppsSort.installTime,
            child: Text(LocaleKeys.android_vpn_apps_sort_install_time.tr()),
          ),
          CheckedPopupMenuItem(
            value: 'sort_update_time',
            checked: sort == AndroidVpnAppsSort.updateTime,
            child: Text(LocaleKeys.android_vpn_apps_sort_update_time.tr()),
          ),
          CheckedPopupMenuItem(
            value: 'sort_reverse',
            checked: reverse,
            child: Text(LocaleKeys.android_vpn_apps_sort_reverse.tr()),
          ),
          const PopupMenuDivider(),
          _menuHeader(context, LocaleKeys.android_vpn_apps_menu_clipboard.tr()),
          PopupMenuItem(
            value: 'import',
            child: Text(LocaleKeys.android_vpn_apps_import.tr()),
          ),
          PopupMenuItem(
            value: 'export',
            child: Text(LocaleKeys.android_vpn_apps_export.tr()),
          ),
        ];
      },
    );
  }

  PopupMenuItem<String> _menuHeader(BuildContext context, String label) {
    return PopupMenuItem<String>(
      enabled: false,
      height: 32,
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  void _onSelected(
    BuildContext context,
    String action,
    ServiceManager services,
  ) {
    final contentState = context.findAncestorStateOfType<_VpnAppsContentState>();
    if (contentState == null) return;
    final selected = services.vpnState.androidVpnApps.value.toSet();
    final appSettings = services.appSettings;

    switch (action) {
      case 'select_all':
        contentState._selectAll(visiblePackages, selected);
      case 'select_none':
        contentState._selectNone(visiblePackages, selected);
      case 'select_invert':
        contentState._selectInvert(visiblePackages, selected);
      case 'show_system':
        appSettings.setAndroidVpnAppsShowSystem(
          !services.vpnState.androidVpnAppsShowSystem.value,
        );
      case 'selected_only':
        appSettings.setAndroidVpnAppsSelectedOnly(
          !services.vpnState.androidVpnAppsSelectedOnly.value,
        );
      case 'sort_name':
        appSettings.setAndroidVpnAppsSort(AndroidVpnAppsSort.name);
      case 'sort_package':
        appSettings.setAndroidVpnAppsSort(AndroidVpnAppsSort.packageName);
      case 'sort_install_time':
        appSettings.setAndroidVpnAppsSort(AndroidVpnAppsSort.installTime);
      case 'sort_update_time':
        appSettings.setAndroidVpnAppsSort(AndroidVpnAppsSort.updateTime);
      case 'sort_reverse':
        appSettings.setAndroidVpnAppsReverse(
          !services.vpnState.androidVpnAppsReverse.value,
        );
      case 'import':
        contentState._importFromClipboard(apps);
      case 'export':
        contentState._exportToClipboard(apps);
    }
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
        errorBuilder: (_, _, _) => const SizedBox(width: 36, height: 36),
      ),
    );
  }
}
