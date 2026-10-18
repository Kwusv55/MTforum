import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/theme_service.dart';
import '../widgets/glass_backdrop.dart';
import '../widgets/liquid_glass.dart';
import 'glass_style.dart';

/// 内置渐变壁纸：一层线性底色 + 几团柔和的径向色块，
/// 纯代码绘制，不占安装包体积，任何分辨率下都清晰。
@immutable
class WallpaperPreset {
  final String key;
  final String name;
  final List<Color> base;
  final List<WallpaperBlob> blobs;

  const WallpaperPreset({
    required this.key,
    required this.name,
    required this.base,
    required this.blobs,
  });

  String get id => '${ThemeService.presetWallpaperPrefix}$key';
}

@immutable
class WallpaperBlob {
  final Color color;
  final Alignment center;
  final double radius;

  const WallpaperBlob(this.color, this.center, [this.radius = 0.9]);
}

const wallpaperPresets = <WallpaperPreset>[
  WallpaperPreset(
    key: 'aurora',
    name: '极光',
    base: [Color(0xFFA8EDEA), Color(0xFFFED6E3)],
    blobs: [
      WallpaperBlob(Color(0xFF7F7FD5), Alignment(-0.9, -0.8)),
      WallpaperBlob(Color(0xFF86A8E7), Alignment(0.9, -0.1)),
      WallpaperBlob(Color(0xFF91EAE4), Alignment(-0.3, 1.0)),
    ],
  ),
  WallpaperPreset(
    key: 'sunset',
    name: '晚霞',
    base: [Color(0xFFFF9A9E), Color(0xFFFAD0C4)],
    blobs: [
      WallpaperBlob(Color(0xFFF6D365), Alignment(0.8, -0.9)),
      WallpaperBlob(Color(0xFFFDA085), Alignment(-0.9, 0.1)),
      WallpaperBlob(Color(0xFFA18CD1), Alignment(0.4, 1.0)),
    ],
  ),
  WallpaperPreset(
    key: 'lavender',
    name: '薰衣草',
    base: [Color(0xFFE0C3FC), Color(0xFF8EC5FC)],
    blobs: [
      WallpaperBlob(Color(0xFFF093FB), Alignment(-0.8, -0.7)),
      WallpaperBlob(Color(0xFFC471F5), Alignment(0.9, 0.3)),
      WallpaperBlob(Color(0xFFFBC2EB), Alignment(-0.4, 1.0)),
    ],
  ),
  WallpaperPreset(
    key: 'mint',
    name: '薄荷',
    base: [Color(0xFFD4FC79), Color(0xFF96E6A1)],
    blobs: [
      WallpaperBlob(Color(0xFF84FAB0), Alignment(0.8, -0.8)),
      WallpaperBlob(Color(0xFF8FD3F4), Alignment(-0.9, 0.2)),
      WallpaperBlob(Color(0xFFE0F7FA), Alignment(0.5, 1.0)),
    ],
  ),
  WallpaperPreset(
    key: 'peach',
    name: '蜜桃',
    base: [Color(0xFFFFECD2), Color(0xFFFCB69F)],
    blobs: [
      WallpaperBlob(Color(0xFFFF8177), Alignment(-0.9, -0.6)),
      WallpaperBlob(Color(0xFFFFD1FF), Alignment(0.9, -0.2)),
      WallpaperBlob(Color(0xFFFAD0C4), Alignment(0.0, 1.0)),
    ],
  ),
  WallpaperPreset(
    key: 'ocean',
    name: '深海',
    base: [Color(0xFF2B5876), Color(0xFF4E4376)],
    blobs: [
      WallpaperBlob(Color(0xFF00C6FF), Alignment(-0.8, -0.7)),
      WallpaperBlob(Color(0xFF0072FF), Alignment(0.9, 0.4)),
      WallpaperBlob(Color(0xFF43E97B), Alignment(-0.4, 1.0), 0.7),
    ],
  ),
  WallpaperPreset(
    key: 'forest',
    name: '森林',
    base: [Color(0xFF134E5E), Color(0xFF71B280)],
    blobs: [
      WallpaperBlob(Color(0xFFA8E063), Alignment(0.8, -0.8)),
      WallpaperBlob(Color(0xFF56AB2F), Alignment(-0.9, 0.3)),
      WallpaperBlob(Color(0xFF2C7744), Alignment(0.4, 1.0)),
    ],
  ),
  WallpaperPreset(
    key: 'midnight',
    name: '午夜',
    base: [Color(0xFF0F0C29), Color(0xFF302B63), Color(0xFF24243E)],
    blobs: [
      WallpaperBlob(Color(0xFF6A3093), Alignment(-0.9, -0.7)),
      WallpaperBlob(Color(0xFFA044FF), Alignment(0.9, 0.1), 0.8),
      WallpaperBlob(Color(0xFF1CB5E0), Alignment(-0.2, 1.0), 0.8),
    ],
  ),
];

WallpaperPreset? findWallpaperPreset(String id) {
  if (!id.startsWith(ThemeService.presetWallpaperPrefix)) return null;
  final key = id.substring(ThemeService.presetWallpaperPrefix.length);
  for (final preset in wallpaperPresets) {
    if (preset.key == key) return preset;
  }
  return null;
}

/// 在 [rect] 里画内置渐变壁纸。页面上的壁纸和玻璃卡片的背景图都用它，
/// 保证两者完全一致。
void paintWallpaperPreset(Canvas canvas, Rect rect, WallpaperPreset preset) {
  canvas.drawRect(
    rect,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: preset.base,
      ).createShader(rect),
  );
  for (final blob in preset.blobs) {
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: blob.center,
          radius: blob.radius,
          colors: [
            blob.color.withValues(alpha: 0.85),
            blob.color.withValues(alpha: 0),
          ],
        ).createShader(rect),
    );
  }
}

/// 整屏壁纸的解码高度（屏幕长边的物理像素）。
int wallpaperDecodeHeight(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  return (math.max(size.width, size.height) *
          MediaQuery.devicePixelRatioOf(context))
      .round();
}

/// 自定义壁纸的图片来源。页面壁纸和玻璃卡片背景用同一个来源，共享解码缓存。
ImageProvider wallpaperFileImage(String path, {required int decodeHeight}) {
  return ResizeImage(
    FileImage(File(path)),
    height: decodeHeight,
    allowUpscaling: false,
  );
}

/// 按壁纸 id 绘制壁纸本身（不含遮罩），铺满父组件。
class WallpaperView extends StatelessWidget {
  final String id;

  /// 缩略图场景传入较小的解码尺寸，避免整张原图进内存。
  final int? decodeHeight;

  const WallpaperView({super.key, required this.id, this.decodeHeight});

  @override
  Widget build(BuildContext context) {
    final preset = findWallpaperPreset(id);
    if (preset != null) return _PresetWallpaper(preset: preset);

    if (id.startsWith(ThemeService.fileWallpaperPrefix)) {
      final path = id.substring(ThemeService.fileWallpaperPrefix.length);
      return Image(
        image: wallpaperFileImage(
          path,
          decodeHeight: decodeHeight ?? wallpaperDecodeHeight(context),
        ),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        errorBuilder: (context, _, __) => ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          child: const Center(child: Icon(Icons.broken_image_outlined)),
        ),
      );
    }
    return const SizedBox.expand();
  }
}

class _PresetWallpaper extends StatelessWidget {
  final WallpaperPreset preset;

  const _PresetWallpaper({required this.preset});

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: CustomPaint(painter: _PresetWallpaperPainter(preset)),
    );
  }
}

class _PresetWallpaperPainter extends CustomPainter {
  final WallpaperPreset preset;

  const _PresetWallpaperPainter(this.preset);

  @override
  void paint(Canvas canvas, Size size) =>
      paintWallpaperPreset(canvas, Offset.zero & size, preset);

  @override
  bool shouldRepaint(_PresetWallpaperPainter oldDelegate) =>
      oldDelegate.preset != preset;
}

/// 给页面铺上当前壁纸和可读性遮罩；没有设置壁纸时原样返回 [child]。
///
/// 每个路由、每个底部 Tab 各自包一层：开启壁纸后 Scaffold 背景是透明的，
/// 如果只在最底层铺一次壁纸，页面切换动画中新旧页面会互相透出来。
class WallpaperBackdrop extends StatefulWidget {
  final Widget child;

  const WallpaperBackdrop({super.key, required this.child});

  @override
  State<WallpaperBackdrop> createState() => _WallpaperBackdropState();
}

class _WallpaperBackdropState extends State<WallpaperBackdrop> {
  // 页面里玻璃卡片的背景图，见 [GlassBackdropSource]。
  final _source = GlassBackdropSource();

  @override
  void dispose() {
    _source.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = GlassStyle.of(context);
    final id = style.wallpaperId;
    final surface = Theme.of(context).colorScheme.surface;

    var page = widget.child;
    if (style.enabled) {
      _source.update(GlassBackdropSpec(
        wallpaperId: id,
        surface: surface,
        dim: style.wallpaperDim,
        refract: style.refraction && LiquidGlassShader.isAvailable,
        saturation: style.saturation,
        blur: style.fallbackBlur,
        devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
        decodeHeight: wallpaperDecodeHeight(context),
      ));
      page = GlassBackdropScope(source: _source, child: page);
    }
    if (id == null) return page;

    return GlassBackdropAnchor(
      source: _source,
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(child: WallpaperView(id: id)),
          ColoredBox(color: surface.withValues(alpha: style.wallpaperDim)),
          page,
        ],
      ),
    );
  }
}
