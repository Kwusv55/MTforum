import 'package:flutter/material.dart';

/// 液态玻璃 / 壁纸相关的主题参数，通过 [ThemeExtension] 下发。
///
/// 放进 ThemeData 而不是让组件直接读 ThemeService：开关玻璃、换壁纸时
/// ThemeData 随之变化，所有依赖 Theme 的组件会自动重建，包括已经压在
/// 导航栈里的旧页面。
///
/// 默认数值来自玻璃实验台选定的「D · 液态折射」方案：
/// 模糊 2 · 饱和度 1.5× · 底色 32% · 亮边 80%/1.5 · 辉光 45% · 投影 14% · 折射 39。
@immutable
class GlassStyle extends ThemeExtension<GlassStyle> {
  /// 是否启用玻璃。关闭时玻璃组件退化为普通不透明表面。
  final bool enabled;

  /// 是否启用边缘折射（需要 Impeller 着色器，设备不支持时为 false）。
  final bool refraction;

  /// 玻璃底色与不透明度。
  final Color tint;
  final double tintOpacity;

  /// 折射模式下的背景模糊半径（逻辑像素）。
  final double blur;

  /// 背景饱和度倍数。
  final double saturation;

  /// 折射带宽度与边缘最大位移（逻辑像素）。
  final double lensBand;
  final double lensDisplacement;

  /// 不支持折射时的磨砂参数：模糊更重、底色更浓，避免背景太乱看不清字。
  final double fallbackBlur;
  final double fallbackTintOpacity;

  /// 亮边、内侧辉光、顶部高光线、投影的强度。
  final double rimOpacity;
  final double rimWidth;
  final double glowOpacity;
  final double highlightOpacity;
  final double shadowOpacity;

  /// 当前壁纸 id，`null` 表示不使用壁纸。
  final String? wallpaperId;

  /// 壁纸遮罩不透明度。
  final double wallpaperDim;

  const GlassStyle({
    required this.enabled,
    required this.refraction,
    required this.tint,
    this.tintOpacity = 0.32,
    this.blur = 2,
    this.saturation = 1.5,
    this.lensBand = 28,
    this.lensDisplacement = 19.5,
    this.fallbackBlur = 10,
    this.fallbackTintOpacity = 0.5,
    this.rimOpacity = 0.8,
    this.rimWidth = 1.5,
    this.glowOpacity = 0.45,
    this.highlightOpacity = 0.9,
    this.shadowOpacity = 0.14,
    this.wallpaperId,
    this.wallpaperDim = 0.35,
  });

  bool get hasWallpaper => wallpaperId != null;

  static GlassStyle of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<GlassStyle>() ??
        GlassStyle(
          enabled: false,
          refraction: false,
          tint: theme.colorScheme.surface,
        );
  }

  @override
  GlassStyle copyWith({
    bool? enabled,
    bool? refraction,
    Color? tint,
    double? tintOpacity,
    String? wallpaperId,
    double? wallpaperDim,
  }) {
    return GlassStyle(
      enabled: enabled ?? this.enabled,
      refraction: refraction ?? this.refraction,
      tint: tint ?? this.tint,
      tintOpacity: tintOpacity ?? this.tintOpacity,
      blur: blur,
      saturation: saturation,
      lensBand: lensBand,
      lensDisplacement: lensDisplacement,
      fallbackBlur: fallbackBlur,
      fallbackTintOpacity: fallbackTintOpacity,
      rimOpacity: rimOpacity,
      rimWidth: rimWidth,
      glowOpacity: glowOpacity,
      highlightOpacity: highlightOpacity,
      shadowOpacity: shadowOpacity,
      wallpaperId: wallpaperId ?? this.wallpaperId,
      wallpaperDim: wallpaperDim ?? this.wallpaperDim,
    );
  }

  @override
  GlassStyle lerp(covariant GlassStyle? other, double t) {
    if (other == null) return this;
    // 开关类字段不插值；颜色和遮罩跟随主题切换动画平滑过渡。
    final base = t < 0.5 ? this : other;
    return base.copyWith(
      tint: Color.lerp(tint, other.tint, t),
      wallpaperDim: wallpaperDim + (other.wallpaperDim - wallpaperDim) * t,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is GlassStyle &&
        other.enabled == enabled &&
        other.refraction == refraction &&
        other.tint == tint &&
        other.tintOpacity == tintOpacity &&
        other.wallpaperId == wallpaperId &&
        other.wallpaperDim == wallpaperDim;
  }

  @override
  int get hashCode => Object.hash(
        enabled,
        refraction,
        tint,
        tintOpacity,
        wallpaperId,
        wallpaperDim,
      );
}
