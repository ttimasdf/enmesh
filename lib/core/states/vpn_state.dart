import 'package:signals_flutter/signals_flutter.dart';

/// Android 分应用 VPN 模式（持久化为 int：0/1/2）
enum AndroidVpnAppMode {
  /// 不启用分应用 VPN，所有应用都走 VPN（默认）
  disabled,

  /// 黑名单：列表内应用不走 VPN，其余应用走 VPN
  denylist,

  /// 白名单：仅列表内应用走 VPN，其余应用不走 VPN
  allowlist;

  static AndroidVpnAppMode fromIndex(int index) {
    if (index < 0 || index >= values.length) {
      return AndroidVpnAppMode.disabled;
    }
    return values[index];
  }

  int get indexValue => index;
}

/// Android VPN 路由状态
class VpnState {
  final androidVpnRoutes = signal<List<String>>([]);
  final androidVpnAppMode = signal<AndroidVpnAppMode>(
    AndroidVpnAppMode.disabled,
  );
  final androidVpnApps = signal<List<String>>([]);

  void setAndroidVpnRoutes(List<String> routes) {
    androidVpnRoutes.value = routes;
  }

  void addAndroidVpnRoute(String route) {
    androidVpnRoutes.value = [...androidVpnRoutes.value, route];
  }

  void removeAndroidVpnRoute(int index) {
    final routes = List<String>.from(androidVpnRoutes.value);
    if (index >= 0 && index < routes.length) {
      routes.removeAt(index);
      androidVpnRoutes.value = routes;
    }
  }

  void setAndroidVpnAppMode(AndroidVpnAppMode mode) {
    androidVpnAppMode.value = mode;
  }

  void setAndroidVpnApps(List<String> packages) {
    androidVpnApps.value = List<String>.from(packages);
  }
}
