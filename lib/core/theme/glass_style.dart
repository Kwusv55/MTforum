import 'package:flutter/material.dart';

/// 液态玻璃 / 壁纸相关的主题参数，通过 [ThemeExtension] 下发。
///
/// 放进 ThemeData 而不是让组件直接读 ThemeService：开关玻璃、换壁纸时
/// ThemeData 随之变化，所有依赖 Theme 的组件会自动重建，包括已经压在
/// 导航栈里的旧页面。
@immutable
class GlassStyle extends ThemeExtension<GlassStyle> {
  /// 是否启用背景模糊。关闭时玻璃组件退化为普通不透明表面。
  final bool enabled;

  /// 背景模糊半径（sigma）。
  final double blurSigma;

  /// 玻璃底色（叠加在模糊结果上的表面色）。
  final Color tint;

  /// 玻璃底色不透明度。越低越通透，越高越像磨砂。
  final double tintOpacity;

  /// 边缘高光颜色（模拟玻璃折射出的亮边）。
  final Color highlight;

  /// 当前壁纸 id，`null` 表示不使用壁纸。
  final String? wallpaperId;

  /// 壁纸遮罩不透明度。
  final double wallpaperDim;

  const GlassStyle({
    required this.enabled,
    required this.blurSigma,
    required this.tint,
    required this.tintOpacity,
    required this.highlight,
    this.wallpaperId,
    this.wallpaperDim = 0.35,
  });

  bool get hasWallpaper => wallpaperId != null;

  static GlassStyle of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<GlassStyle>() ??
        GlassStyle(
          enabled: false,
          blurSigma: 0,
          tint: theme.colorScheme.surface,
          tintOpacity: 1,
          highlight: Colors.white,
        );
  }

  @override
  GlassStyle copyWith({
    bool? enabled,
    double? blurSigma,
    Color? tint,
    double? tintOpacity,
    Color? highlight,
    String? wallpaperId,
    double? wallpaperDim,
  }) {
    return GlassStyle(
      enabled: enabled ?? this.enabled,
      blurSigma: blurSigma ?? this.blurSigma,
      tint: tint ?? this.tint,
      tintOpacity: tintOpacity ?? this.tintOpacity,
      highlight: highlight ?? this.highlight,
      wallpaperId: wallpaperId ?? this.wallpaperId,
      wallpaperDim: wallpaperDim ?? this.wallpaperDim,
    );
  }

  @override
  GlassStyle lerp(covariant GlassStyle? other, double t) {
    if (other == null) return this;
    return GlassStyle(
      enabled: t < 0.5 ? enabled : other.enabled,
      blurSigma: lerpDouble(blurSigma, other.blurSigma, t),
      tint: Color.lerp(tint, other.tint, t)!,
      tintOpacity: lerpDouble(tintOpacity, other.tintOpacity, t),
      highlight: Color.lerp(highlight, other.highlight, t)!,
      wallpaperId: t < 0.5 ? wallpaperId : other.wallpaperId,
      wallpaperDim: lerpDouble(wallpaperDim, other.wallpaperDim, t),
    );
  }

  static double lerpDouble(double a, double b, double t) => a + (b - a) * t;

  @override
  bool operator ==(Object other) {
    return other is GlassStyle &&
        other.enabled == enabled &&
        other.blurSigma == blurSigma &&
        other.tint == tint &&
        other.tintOpacity == tintOpacity &&
        other.highlight == highlight &&
        other.wallpaperId == wallpaperId &&
        other.wallpaperDim == wallpaperDim;
  }

  @override
  int get hashCode => Object.hash(
        enabled,
        blurSigma,
        tint,
        tintOpacity,
        highlight,
        wallpaperId,
        wallpaperDim,
      );
}
