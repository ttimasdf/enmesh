import 'dart:typed_data';

/// 设备上可被分应用 VPN 选中的应用描述。
class InstalledApp {
  /// 应用包名，例如 com.example.app
  final String packageName;

  /// 应用显示名称
  final String label;

  /// 应用图标 PNG 字节（可能为空）
  final Uint8List? icon;

  /// 是否为系统（预装）应用
  final bool system;

  /// 首次安装时间（Unix 毫秒）
  final int installTime;

  /// 最近更新时间（Unix 毫秒）
  final int updateTime;

  const InstalledApp({
    required this.packageName,
    required this.label,
    this.icon,
    this.system = false,
    this.installTime = 0,
    this.updateTime = 0,
  });

  factory InstalledApp.fromMap(Map<Object?, Object?> map) {
    final icon = map['icon'];
    final system = map['system'];
    final installTime = map['installTime'];
    final updateTime = map['updateTime'];
    return InstalledApp(
      packageName: map['packageName']?.toString() ?? '',
      label: map['label']?.toString() ?? '',
      icon: icon is Uint8List ? icon : null,
      system: system is bool ? system : false,
      installTime: installTime is num ? installTime.toInt() : 0,
      updateTime: updateTime is num ? updateTime.toInt() : 0,
    );
  }
}
