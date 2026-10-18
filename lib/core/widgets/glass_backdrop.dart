import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../services/theme_service.dart';
import '../theme/wallpapers.dart';

/// 玻璃背景的饱和度矩阵，按饱和度缓存。
ui.ColorFilter glassSaturationFilter(double s) {
  return _saturationFilters.putIfAbsent(s, () {
    final m = _saturationMatrix(s);
    return ui.ColorFilter.matrix(m);
  });
}

final Map<double, ui.ColorFilter> _saturationFilters = {};

List<double> _saturationMatrix(double s) {
  const r = 0.2126, g = 0.7152, b = 0.0722;
  final ir = (1 - s) * r, ig = (1 - s) * g, ib = (1 - s) * b;
  return [
    ir + s, ig, ib, 0, 0, //
    ir, ig + s, ib, 0, 0, //
    ir, ig, ib + s, 0, 0, //
    0, 0, 0, 1, 0, //
  ];
}

Color _saturateColor(Color c, double s) {
  final m = _saturationMatrix(s);
  double ch(int row) =>
      (m[row * 5] * c.r + m[row * 5 + 1] * c.g + m[row * 5 + 2] * c.b)
          .clamp(0.0, 1.0);
  return Color.from(alpha: c.a, red: ch(0), green: ch(1), blue: ch(2));
}

/// 生成页面背景图所需的全部参数，任何一项变化都要重画。
@immutable
class GlassBackdropSpec {
  /// 当前壁纸；为 null 时页面背景就是纯色 [surface]。
  final String? wallpaperId;
  final Color surface;
  final double dim;

  /// 折射模式：图里只放壁纸和遮罩，模糊和饱和度交给着色器；
  /// 否则把磨砂模糊 [blur] 和饱和度直接画进图里。
  final bool refract;
  final double saturation;
  final double blur;
  final double devicePixelRatio;
  final int decodeHeight;

  const GlassBackdropSpec({
    required this.wallpaperId,
    required this.surface,
    required this.dim,
    required this.refract,
    required this.saturation,
    required this.blur,
    required this.devicePixelRatio,
    required this.decodeHeight,
  });

  /// 图片每逻辑像素的像素数。折射模式要看清背后细节，用物理分辨率；
  /// 磨砂模式整张都是糊的，四分之一就够。
  double get scale => devicePixelRatio * (refract ? 1 : 0.25);

  @override
  bool operator ==(Object other) =>
      other is GlassBackdropSpec &&
      other.wallpaperId == wallpaperId &&
      other.surface == surface &&
      other.dim == dim &&
      other.refract == refract &&
      other.saturation == saturation &&
      other.blur == blur &&
      other.devicePixelRatio == devicePixelRatio &&
      other.decodeHeight == decodeHeight;

  @override
  int get hashCode => Object.hash(wallpaperId, surface, dim, refract,
      saturation, blur, devicePixelRatio, decodeHeight);
}

/// 页面玻璃卡片的背景来源，每个路由（每个底部 Tab）一份，由
/// [WallpaperBackdrop] 持有。
///
/// 卡片背后只有静止的壁纸和遮罩，不必像悬浮的顶栏那样每帧用背景滤镜读
/// 屏幕：这里预先把「壁纸 + 遮罩」画成一张图，卡片按自己相对页面的位置
/// 取对应那一块。页面切换时卡片和壁纸一起移动，相对位置不变，不用重画。
/// 实测底栏切换时，每张卡片每帧一次的背景读取是掉帧的主要来源。
class GlassBackdropSource extends ChangeNotifier {
  GlassBackdropSpec? _spec;
  RenderBox? _anchor;
  Size? _size;
  _ImageKey? _key;
  ui.Image? _image;
  double _imageScale = 1;
  Color? _solid;
  bool _refreshScheduled = false;
  bool _disposed = false;

  /// 没有壁纸时页面背景是纯色（此时 [image] 是这个颜色的 1×1 图，不需要对位）。
  Color? get solid => _solid;

  /// 「壁纸 + 遮罩」图；还没画好时为 null，卡片暂时只显示玻璃底色。
  ui.Image? get image => _image;

  /// [image] 每逻辑像素的像素数。
  double get scale => _imageScale;

  /// [image] 是否按折射模式生成（未模糊，由着色器处理）。
  bool get refract => _spec?.refract ?? false;

  /// 页面坐标原点：卡片位置都相对它计算，与壁纸的铺放区域一致。
  RenderBox? get anchor => _anchor;

  void update(GlassBackdropSpec spec) {
    if (spec == _spec) return;
    _spec = spec;
    if (spec.wallpaperId == null) {
      _setSolid(_saturateColor(spec.surface, spec.saturation));
    } else {
      _scheduleRefresh();
    }
  }

  void _attachAnchor(RenderBox anchor, Size size) {
    if (identical(anchor, _anchor) && size == _size) return;
    _anchor = anchor;
    _size = size;
    _scheduleRefresh();
  }

  void _detachAnchor(RenderBox anchor) {
    if (identical(anchor, _anchor)) _anchor = null;
  }

  void _setSolid(Color color) {
    if (_solid == color && _image != null) return;
    _releaseImage();
    _solid = color;
    // 纯色也做成 1×1 的图，卡片就和有壁纸时走同一条绘制路径。
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(color, BlendMode.src);
    final picture = recorder.endRecording();
    _image = picture.toImageSync(1, 1);
    picture.dispose();
    _imageScale = 1;
    notifyListeners();
  }

  // 生成图片可能要解码壁纸，放到当前帧之后做，避免在布局/构建中途干重活。
  void _scheduleRefresh() {
    if (_refreshScheduled) return;
    _refreshScheduled = true;
    scheduleMicrotask(() {
      _refreshScheduled = false;
      if (!_disposed) _refresh();
    });
  }

  void _refresh() {
    final spec = _spec;
    final size = _size;
    if (spec == null || spec.wallpaperId == null) return;
    if (size == null || size.isEmpty) return;

    final key = _ImageKey(spec, size);
    if (key == _key) return;
    if (_key != null) _BackdropImageCache.release(_key!);
    _key = key;
    _solid = null;

    _BackdropImageCache.acquire(key).then((master) {
      if (_disposed || _key != key) return;
      _image?.dispose();
      _image = master?.clone();
      _imageScale = key.spec.scale;
      notifyListeners();
    });
  }

  void _releaseImage() {
    if (_key != null) _BackdropImageCache.release(_key!);
    _key = null;
    _image?.dispose();
    _image = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _releaseImage();
    super.dispose();
  }
}

/// 把 [GlassBackdropSource] 提供给页面里的玻璃卡片。
class GlassBackdropScope extends InheritedWidget {
  final GlassBackdropSource source;

  const GlassBackdropScope({
    super.key,
    required this.source,
    required super.child,
  });

  static GlassBackdropSource? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<GlassBackdropScope>()
      ?.source;

  @override
  bool updateShouldNotify(GlassBackdropScope oldWidget) =>
      source != oldWidget.source;
}

/// 标出页面坐标原点（壁纸铺放的区域），并把它的尺寸报给 [source]。
class GlassBackdropAnchor extends SingleChildRenderObjectWidget {
  final GlassBackdropSource source;

  const GlassBackdropAnchor({
    super.key,
    required this.source,
    super.child,
  });

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderBackdropAnchor(source);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderBackdropAnchor).source = source;
  }
}

class _RenderBackdropAnchor extends RenderProxyBox {
  _RenderBackdropAnchor(this._source);

  GlassBackdropSource _source;

  set source(GlassBackdropSource value) {
    if (identical(value, _source)) return;
    _source._detachAnchor(this);
    _source = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    super.performLayout();
    _source._attachAnchor(this, size);
  }

  @override
  void detach() {
    _source._detachAnchor(this);
    super.detach();
  }
}

@immutable
class _ImageKey {
  final GlassBackdropSpec spec;
  final Size size;

  const _ImageKey(this.spec, this.size);

  @override
  bool operator ==(Object other) =>
      other is _ImageKey && other.spec == spec && other.size == size;

  @override
  int get hashCode => Object.hash(spec, size);
}

/// 同样参数、同样尺寸的页面共用一张图（四个 Tab 和打开的各个页面通常
/// 都一样），按引用计数释放。
abstract final class _BackdropImageCache {
  static final _entries = <_ImageKey, _CacheEntry>{};

  static Future<ui.Image?> acquire(_ImageKey key) {
    final entry = _entries.putIfAbsent(key, () => _CacheEntry(key));
    entry.refs++;
    return entry.future;
  }

  static void release(_ImageKey key) {
    final entry = _entries[key];
    if (entry == null) return;
    if (--entry.refs > 0) return;
    _entries.remove(key);
    entry.dispose();
  }
}

class _CacheEntry {
  _CacheEntry(_ImageKey key) {
    future = _render(key).then((image) {
      if (_disposed) {
        image?.dispose();
        return null;
      }
      _image = image;
      return image;
    }, onError: (Object _) => null);
  }

  late final Future<ui.Image?> future;
  int refs = 0;
  ui.Image? _image;
  bool _disposed = false;

  void dispose() {
    _disposed = true;
    _image?.dispose();
    _image = null;
  }

  static Future<ui.Image?> _render(_ImageKey key) async {
    final spec = key.spec;
    final id = spec.wallpaperId!;
    final width = (key.size.width * spec.scale).ceil();
    final height = (key.size.height * spec.scale).ceil();
    if (width <= 0 || height <= 0) return null;

    final preset = findWallpaperPreset(id);
    ui.Image? photo;
    if (preset == null) {
      if (!id.startsWith(ThemeService.fileWallpaperPrefix)) return null;
      final path = id.substring(ThemeService.fileWallpaperPrefix.length);
      photo = await _decode(
        wallpaperFileImage(path, decodeHeight: spec.decodeHeight),
      );
      if (photo == null) return null;
    }

    final rect = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, rect);
    if (!spec.refract) {
      // 与卡片原来的背景滤镜一致：先模糊、再提饱和度。
      final sigma = spec.blur * spec.scale;
      canvas.saveLayer(
        rect,
        Paint()
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: sigma,
            sigmaY: sigma,
            tileMode: TileMode.clamp,
          )
          ..colorFilter = glassSaturationFilter(spec.saturation),
      );
    }
    if (preset != null) {
      paintWallpaperPreset(canvas, rect, preset);
    } else {
      // 与 WallpaperView 的 Image(fit: cover) 铺法相同。
      paintImage(
        canvas: canvas,
        rect: rect,
        image: photo!,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
      );
      photo.dispose();
    }
    canvas.drawRect(rect, Paint()..color = spec.surface.withValues(alpha: spec.dim));
    if (!spec.refract) canvas.restore();

    final picture = recorder.endRecording();
    final image = picture.toImageSync(width, height);
    picture.dispose();
    return image;
  }

  static Future<ui.Image?> _decode(ImageProvider provider) {
    final completer = Completer<ui.Image?>();
    final stream = provider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        stream.removeListener(listener);
        if (completer.isCompleted) {
          info.dispose();
        } else {
          completer.complete(info.image);
        }
      },
      onError: (_, __) {
        stream.removeListener(listener);
        if (!completer.isCompleted) completer.complete(null);
      },
    );
    stream.addListener(listener);
    return completer.future;
  }
}
