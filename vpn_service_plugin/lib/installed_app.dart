import 'dart:typed_data';

/// 设备上可被分应用 VPN 选中的应用描述。
class InstalledApp {
  /// 应用包名，例如 com.example.app
  final String packageName;

  /// 应用显示名称
  final String label;

  /// 应用图标 PNG 字节（可能为空）
  final Uint8List? icon;

  const InstalledApp({
    required this.packageName,
    required this.label,
    this.icon,
  });

  factory InstalledApp.fromMap(Map<Object?, Object?> map) {
    final icon = map['icon'];
    return InstalledApp(
      packageName: map['packageName']?.toString() ?? '',
      label: map['label']?.toString() ?? '',
      icon: icon is Uint8List ? icon : null,
    );
  }
}
