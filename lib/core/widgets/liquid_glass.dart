import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../theme/glass_style.dart';
import 'glass_backdrop.dart';

/// 玻璃面板参与折射和高光的边。
enum GlassEdge {
  /// 整圈（悬浮胶囊）。
  all,

  /// 只有顶边（底部弹层、贴底输入栏）。
  top,
}

/// 液态折射着色器。启动时加载一次；设备不支持（非 Impeller）或加载失败时
/// [isAvailable] 为 false，玻璃组件自动退化为普通磨砂。
///
/// 两个版本：[_program] 读屏幕背景（悬浮的顶栏、底栏），
/// [_imageProgram] 从页面壁纸图取样（页面里的卡片，见 [GlassBackdropSource]）。
abstract final class LiquidGlassShader {
  static ui.FragmentProgram? _program;
  static ui.FragmentProgram? _imageProgram;

  static bool get isAvailable => _program != null && _imageProgram != null;

  static Future<void> load() async {
    if (isAvailable || !ui.ImageFilter.isShaderFilterSupported) return;
    try {
      final programs = await Future.wait([
        ui.FragmentProgram.fromAsset('shaders/liquid_glass.frag'),
        ui.FragmentProgram.fromAsset('shaders/liquid_glass_image.frag'),
      ]);
      _program = programs[0];
      _imageProgram = programs[1];
    } catch (_) {
      _program = null;
      _imageProgram = null;
    }
  }
}

/// 液态玻璃面板。
///
/// 支持折射时：背景经着色器做边缘透镜折射 + 轻微模糊 + 饱和度增强，
/// 叠半透明底色、白色亮边、内侧辉光和镜面反光。
/// 不支持时：系统模糊 + 更浓的底色（磨砂效果）。
/// 主题关闭玻璃时：不透明 [fallbackColor]，不创建任何背景滤镜。
class LiquidGlass extends StatelessWidget {
  final Widget? child;
  final BorderRadius borderRadius;
  final GlassEdge edge;

  /// 悬浮在内容上方的面板（顶栏、底栏胶囊）加一层柔和投影。
  final bool elevated;

  /// 在主题默认不透明度上再加一点，用于承载大段文字的面板（评论区）。
  final double opacityBoost;

  /// 关闭玻璃效果时使用的颜色，默认 `surfaceContainerLow`。
  final Color? fallbackColor;

  /// 直接放在页面上、背后只有壁纸的面板（页面里的卡片）：背景从页面预先
  /// 画好的壁纸图里取（见 [GlassBackdropSource]），不读屏幕。
  /// 悬浮在内容上方的顶栏、底栏，以及嵌在其它玻璃里的面板要读真实背景，
  /// 保持 false。
  final bool onPage;

  const LiquidGlass({
    super.key,
    this.child,
    this.borderRadius = BorderRadius.zero,
    this.edge = GlassEdge.all,
    this.elevated = false,
    this.opacityBoost = 0,
    this.fallbackColor,
    this.onPage = false,
  });

  /// 卡片所在的所有滚动视图：滚动时卡片相对壁纸移动，要立即重画背景。
  static Listenable? _scrollPositions(BuildContext context) {
    final positions = <Listenable>[];
    var scrollable = Scrollable.maybeOf(context);
    while (scrollable != null) {
      positions.add(scrollable.position);
      scrollable = Scrollable.maybeOf(scrollable.context);
    }
    if (positions.isEmpty) return null;
    return positions.length == 1
        ? positions.single
        : Listenable.merge(positions);
  }

  @override
  Widget build(BuildContext context) {
    final style = GlassStyle.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    if (!style.enabled) {
      final panel = DecoratedBox(
        decoration: BoxDecoration(
          color: fallbackColor ?? scheme.surfaceContainerLow,
          borderRadius: borderRadius,
          border: edge == GlassEdge.all
              ? Border.all(color: scheme.outlineVariant)
              : null,
        ),
        child: child,
      );
      return ClipRRect(borderRadius: borderRadius, child: panel);
    }

    final refract = style.refraction && LiquidGlassShader.isAvailable;
    final tint = ((refract ? style.tintOpacity : style.fallbackTintOpacity) +
            opacityBoost)
        .clamp(0.0, 1.0);

    final tintTop = (tint + 0.06).clamp(0.0, 1.0);
    final tintBottom = (tint - 0.04).clamp(0.0, 1.0);

    final source = onPage ? GlassBackdropScope.maybeOf(context) : null;
    // 页面卡片在着色器里一次画完底色、反光和辉光（见 liquid_glass_image.frag），
    // 这里只留便宜的亮边和高光线。
    final inShader = source != null && LiquidGlassShader.isAvailable;

    final body = CustomPaint(
      foregroundPainter: _GlassDecorPainter(
        borderRadius: borderRadius,
        edge: edge,
        dark: isDark,
        rim: style.rimOpacity,
        rimWidth: style.rimWidth,
        glow: inShader ? 0 : style.glowOpacity,
        highlight: style.highlightOpacity,
        specular: refract && !inShader,
      ),
      child: inShader
          ? child
          : DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    style.tint.withValues(alpha: tintTop),
                    style.tint.withValues(alpha: tintBottom),
                  ],
                ),
              ),
              child: child,
            ),
    );

    Widget panel;
    if (source != null) {
      panel = _WallpaperGlass(
        source: source,
        scroll: _scrollPositions(context),
        borderRadius: borderRadius,
        edge: edge,
        blur: style.blur,
        saturation: style.saturation,
        band: style.lensBand,
        displacement: style.lensDisplacement,
        decor: inShader
            ? _ShaderDecor(
                tint: style.tint,
                tintTop: tintTop,
                tintBottom: tintBottom,
                specularTop: refract ? (isDark ? 0.25 : 0.55) : 0,
                specularBottom: refract && edge == GlassEdge.all
                    ? (isDark ? 0.12 : 0.25)
                    : 0,
                glow: isDark ? style.glowOpacity * 0.12 : style.glowOpacity,
              )
            : null,
        // 背景随滚动重画时，卡片里的内容不必跟着重新录制。
        child: RepaintBoundary(child: body),
      );
    } else if (refract) {
      panel = _RefractiveBackdrop(
        borderRadius: borderRadius,
        edge: edge,
        blur: style.blur,
        saturation: style.saturation,
        band: style.lensBand,
        displacement: style.lensDisplacement,
        devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
        child: body,
      );
    } else {
      panel = ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ui.ImageFilter.compose(
            outer: glassSaturationFilter(style.saturation),
            inner: ui.ImageFilter.blur(
              sigmaX: style.fallbackBlur,
              sigmaY: style.fallbackBlur,
            ),
          ),
          child: body,
        ),
      );
    }

    if (!elevated) return panel;
    final shadow = style.shadowOpacity * (isDark ? 2.2 : 1);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: shadow.clamp(0.0, 1.0)),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: panel,
    );
  }
}

/// 页面里的卡片。玻璃模式下是与顶栏同款的液态玻璃面板，否则就是普通 [Card]，
/// 参数含义与 [Card] 一致。
///
/// 玻璃模式下 [color] 不生效（底色由玻璃决定）；需要标出未读、高亮时用
/// [glassColor] 在玻璃上叠一层强调色，此时 [shape] 的描边也会保留。
class GlassCard extends StatelessWidget {
  final Widget? child;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final Color? glassColor;
  final ShapeBorder? shape;
  final double? elevation;
  final Clip? clipBehavior;

  /// 承载大段正文的卡片（帖子）可加一点底色，保证压在花哨壁纸上也看得清。
  final double opacityBoost;

  /// 见 [LiquidGlass.onPage]；嵌在其它玻璃里的卡片要传 false。
  final bool onPage;

  /// 传 false 时始终是普通 [Card]（已经压在玻璃弹层上的卡片）。
  final bool glass;

  const GlassCard({
    super.key,
    this.glass = true,
    this.child,
    this.margin,
    this.color,
    this.glassColor,
    this.shape,
    this.elevation,
    this.clipBehavior,
    this.opacityBoost = 0,
    this.onPage = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!glass || !GlassStyle.of(context).enabled) {
      return Card(
        margin: margin,
        color: color,
        shape: shape,
        elevation: elevation,
        clipBehavior: clipBehavior,
        child: child,
      );
    }

    final cardTheme = CardTheme.of(context);
    final resolved = shape ?? cardTheme.shape;
    final borderRadius = resolved is RoundedRectangleBorder
        ? resolved.borderRadius.resolve(Directionality.maybeOf(context))
        : const BorderRadius.all(Radius.circular(20));
    final side = resolved is OutlinedBorder ? resolved.side : BorderSide.none;
    final accent = glassColor;

    Widget content = Material(
      type: MaterialType.transparency,
      child: child,
    );
    if (accent != null) {
      content = DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          border: side.style == BorderStyle.none
              ? null
              : Border.fromBorderSide(side),
        ),
        child: ColoredBox(color: accent, child: content),
      );
    }

    return Padding(
      padding: margin ?? cardTheme.margin ?? EdgeInsets.zero,
      child: LiquidGlass(
        borderRadius: borderRadius,
        opacityBoost: opacityBoost,
        onPage: onPage,
        child: content,
      ),
    );
  }
}

/// 绘制白色亮边、内侧辉光、顶部高光线和镜面反光。
class _GlassDecorPainter extends CustomPainter {
  final BorderRadius borderRadius;
  final GlassEdge edge;
  final bool dark;
  final double rim;
  final double rimWidth;
  final double glow;
  final double highlight;
  final bool specular;

  const _GlassDecorPainter({
    required this.borderRadius,
    required this.edge,
    required this.dark,
    required this.rim,
    required this.rimWidth,
    required this.glow,
    required this.highlight,
    required this.specular,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    if (rect.isEmpty) return;
    final w = size.width, h = size.height;

    // 深色模式下白光要收敛很多，否则发灰发雾。
    final rimA = dark ? rim * 0.28 : rim;
    final glowA = dark ? glow * 0.12 : glow;
    final hlA = dark ? highlight * 0.35 : highlight;

    // 只画顶边的面板（弹层、输入栏）用纵向渐变把亮边收在顶部。
    Shader? topOnly(double stop) => edge == GlassEdge.top
        ? LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: const [Colors.white, Color(0x00FFFFFF)],
            stops: [0, stop],
          ).createShader(rect)
        : null;

    // 镜面反光：左上一大片、右下一小片，柔光混合。
    if (specular) {
      void ellipse(double cx, double cy, double rx, double ry, double a) {
        canvas.save();
        canvas.translate(cx, cy);
        canvas.scale(rx / ry, 1);
        canvas.drawCircle(
          Offset.zero,
          ry,
          Paint()
            ..blendMode = BlendMode.softLight
            ..shader = RadialGradient(
              colors: [
                Colors.white.withValues(alpha: a),
                Colors.white.withValues(alpha: 0),
              ],
            ).createShader(Rect.fromCircle(center: Offset.zero, radius: ry)),
        );
        canvas.restore();
      }

      // 反光按胶囊高度设计，高的卡片只在顶部和底部各留一片同样大小的光。
      final sh = math.min(h, 120.0);
      canvas.save();
      canvas.clipRRect(borderRadius.toRRect(rect));
      ellipse(w * 0.18, -sh * 0.10, w * 0.54, sh * 0.405, dark ? 0.25 : 0.55);
      if (edge == GlassEdge.all) {
        ellipse(w, h + sh * 0.2, w * 0.45, sh * 0.40, dark ? 0.12 : 0.25);
      }
      canvas.restore();
    }

    // 内侧辉光：沿边缘一圈柔和白光向内渐隐（外半圈由父级裁剪掉）。
    if (glowA > 0) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6)
        ..color = Colors.white.withValues(alpha: glowA);
      final shader = topOnly(0.35);
      if (shader != null) {
        canvas.saveLayer(rect, Paint());
        canvas.drawRRect(borderRadius.toRRect(rect), paint);
        canvas.drawRect(
            rect,
            Paint()
              ..blendMode = BlendMode.dstIn
              ..shader = shader);
        canvas.restore();
      } else {
        canvas.save();
        canvas.clipRRect(borderRadius.toRRect(rect));
        canvas.drawRRect(borderRadius.toRRect(rect), paint);
        canvas.restore();
      }
    }

    // 顶部 1px 高光线，模拟光从上方照在玻璃边缘。
    if (hlA > 0) {
      final inset = rect.deflate(rimWidth + 0.5);
      canvas.drawRRect(
        borderRadius.toRRect(inset).shift(const Offset(0, 0.5)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withValues(alpha: hlA),
              Colors.white.withValues(alpha: 0),
            ],
            stops: const [0, 0.35],
          ).createShader(inset),
      );
    }

    // 白色亮边。
    if (rimA > 0 && rimWidth > 0) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = rimWidth
        ..color = Colors.white.withValues(alpha: rimA);
      final shader = topOnly(0.12);
      if (shader != null) {
        paint.shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: rimA),
            Colors.white.withValues(alpha: 0),
          ],
          stops: const [0, 0.12],
        ).createShader(rect);
      }
      canvas.drawRRect(
        borderRadius.toRRect(rect.deflate(rimWidth / 2)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_GlassDecorPainter old) {
    return old.borderRadius != borderRadius ||
        old.edge != edge ||
        old.dark != dark ||
        old.rim != rim ||
        old.rimWidth != rimWidth ||
        old.glow != glow ||
        old.highlight != highlight ||
        old.specular != specular;
  }
}

/// 用折射着色器处理自身区域的背景。
class _RefractiveBackdrop extends SingleChildRenderObjectWidget {
  final BorderRadius borderRadius;
  final GlassEdge edge;
  final double blur;
  final double saturation;
  final double band;
  final double displacement;
  final double devicePixelRatio;

  const _RefractiveBackdrop({
    required this.borderRadius,
    required this.edge,
    required this.blur,
    required this.saturation,
    required this.band,
    required this.displacement,
    required this.devicePixelRatio,
    super.child,
  });

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderRefractiveBackdrop(
      shader: LiquidGlassShader._program!.fragmentShader(),
    )..update(this);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderRefractiveBackdrop renderObject,
  ) {
    renderObject.update(this);
  }
}

class _RenderRefractiveBackdrop extends RenderProxyBox {
  _RenderRefractiveBackdrop({required ui.FragmentShader shader})
      : _shader = shader;

  final ui.FragmentShader _shader;
  final _clipLayer = LayerHandle<ClipRRectLayer>();
  final _filterLayer = LayerHandle<BackdropFilterLayer>();

  BorderRadius _borderRadius = BorderRadius.zero;
  GlassEdge _edge = GlassEdge.all;
  double _blur = 0;
  double _saturation = 1;
  double _band = 0;
  double _displacement = 0;
  double _dpr = 1;

  /// 最近一次绘制时自身在屏幕上的位置。
  Rect? _paintedRect;

  /// 页面切换、弹层滑入等移动过程中，图层被整体平移而不会重新绘制，
  /// 着色器里的形状位置会滞后一帧。移动期间关闭折射只保留模糊，
  /// 停稳后再打开，避免边缘错位闪烁。
  bool _moving = false;

  /// 停稳后折射强度从 0 渐变到 1，滚动停下时边缘不会突然冒出来。
  double _settle = 1;

  void update(_RefractiveBackdrop w) {
    if (_borderRadius == w.borderRadius &&
        _edge == w.edge &&
        _blur == w.blur &&
        _saturation == w.saturation &&
        _band == w.band &&
        _displacement == w.displacement &&
        _dpr == w.devicePixelRatio) {
      return;
    }
    _borderRadius = w.borderRadius;
    _edge = w.edge;
    _blur = w.blur;
    _saturation = w.saturation;
    _band = w.band;
    _displacement = w.displacement;
    _dpr = w.devicePixelRatio;
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _GlassMotionTracker.add(this);
  }

  @override
  void detach() {
    _GlassMotionTracker.remove(this);
    super.detach();
  }

  @override
  void dispose() {
    _clipLayer.layer = null;
    _filterLayer.layer = null;
    _shader.dispose();
    super.dispose();
  }

  Rect _globalRect() =>
      MatrixUtils.transformRect(getTransformTo(null), Offset.zero & size);

  void _checkMotion() {
    final painted = _paintedRect;
    if (!attached || !hasSize || painted == null) return;
    final now = _globalRect();
    if (now != painted) {
      _moving = true;
      _settle = 0;
      markNeedsPaint();
    } else if (_moving) {
      _moving = false;
      markNeedsPaint();
    } else if (_settle < 1) {
      _settle = math.min(1, _settle + 0.12);
      markNeedsPaint();
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final global = _globalRect();
    _paintedRect = global;

    // 只折射顶边的面板：把其余三边推到很远，SDF 在那些边上就不会产生透镜。
    final lens = _edge == GlassEdge.top
        ? Rect.fromLTRB(
            global.left - 2000,
            global.top,
            global.right + 2000,
            global.bottom + 2000,
          )
        : global;
    final radius = _edge == GlassEdge.top ? 0.0 : _borderRadius.topLeft.x;
    final band = math.min(_band, size.shortestSide / 2);
    final d = _dpr;
    final settle = Curves.easeOut.transform(_settle);

    _shader
      ..setFloat(2, lens.left * d)
      ..setFloat(3, lens.top * d)
      ..setFloat(4, lens.width * d)
      ..setFloat(5, lens.height * d)
      ..setFloat(6, radius * d)
      ..setFloat(7, band * d)
      ..setFloat(8, _moving ? 0 : _displacement * settle * d)
      ..setFloat(9, _blur * d)
      ..setFloat(10, _saturation);

    final bounds = Offset.zero & size;
    _clipLayer.layer = context.pushClipRRect(
      needsCompositing,
      offset,
      bounds,
      _borderRadius.toRRect(bounds),
      (context, offset) {
        final layer = _filterLayer.layer ??= BackdropFilterLayer();
        layer.filter = ui.ImageFilter.shader(_shader);
        context.pushLayer(layer, super.paint, offset);
      },
      oldLayer: _clipLayer.layer,
    );
  }
}

/// 每帧绘制完成后检查折射面板是否被移动过（见 [_RenderRefractiveBackdrop._moving]）。
abstract final class _GlassMotionTracker {
  static final _objects = <_RenderRefractiveBackdrop>{};
  static bool _registered = false;

  static void add(_RenderRefractiveBackdrop object) {
    _objects.add(object);
    if (_registered) return;
    _registered = true;
    SchedulerBinding.instance.addPersistentFrameCallback((_) {
      if (_objects.isEmpty) return;
      for (final object in _objects.toList(growable: false)) {
        object._checkMotion();
      }
    });
  }

  static void remove(_RenderRefractiveBackdrop object) =>
      _objects.remove(object);
}

/// 页面卡片在着色器里画的部分：底色渐变、镜面反光、内侧辉光。
@immutable
class _ShaderDecor {
  final Color tint;
  final double tintTop;
  final double tintBottom;
  final double specularTop;
  final double specularBottom;
  final double glow;

  const _ShaderDecor({
    required this.tint,
    required this.tintTop,
    required this.tintBottom,
    required this.specularTop,
    required this.specularBottom,
    required this.glow,
  });

  @override
  bool operator ==(Object other) =>
      other is _ShaderDecor &&
      other.tint == tint &&
      other.tintTop == tintTop &&
      other.tintBottom == tintBottom &&
      other.specularTop == specularTop &&
      other.specularBottom == specularBottom &&
      other.glow == glow;

  @override
  int get hashCode => Object.hash(
      tint, tintTop, tintBottom, specularTop, specularBottom, glow);
}

/// 页面卡片的背景：从 [GlassBackdropSource] 的壁纸图里取自己位置那一块。
///
/// 有 [decor] 时经壁纸采样版着色器一次画完背景、底色、反光和辉光；
/// 没有时（设备不支持着色器）直接贴图，底色和装饰由外层组件照旧绘制。
class _WallpaperGlass extends SingleChildRenderObjectWidget {
  final GlassBackdropSource source;
  final Listenable? scroll;
  final BorderRadius borderRadius;
  final GlassEdge edge;
  final double blur;
  final double saturation;
  final double band;
  final double displacement;
  final _ShaderDecor? decor;

  const _WallpaperGlass({
    required this.source,
    required this.scroll,
    required this.borderRadius,
    required this.edge,
    required this.blur,
    required this.saturation,
    required this.band,
    required this.displacement,
    required this.decor,
    super.child,
  });

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderWallpaperGlass()..update(this);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderWallpaperGlass renderObject,
  ) {
    renderObject.update(this);
  }
}

class _RenderWallpaperGlass extends RenderProxyBox {
  GlassBackdropSource? _source;
  Listenable? _scroll;
  BorderRadius _borderRadius = BorderRadius.zero;
  GlassEdge _edge = GlassEdge.all;
  double _blur = 0;
  double _saturation = 1;
  double _band = 0;
  double _displacement = 0;
  _ShaderDecor? _decor;

  ui.FragmentShader? _shader;
  final _clipLayer = LayerHandle<ClipRRectLayer>();

  /// 最近一次绘制时自身在页面里的位置；位置变了背景就要重画。
  Offset? _paintedOrigin;

  void update(_WallpaperGlass w) {
    if (!identical(_source, w.source)) {
      if (attached) _source?.removeListener(markNeedsPaint);
      _source = w.source;
      if (attached) _source!.addListener(markNeedsPaint);
      markNeedsPaint();
    }
    if (!identical(_scroll, w.scroll)) {
      if (attached) _scroll?.removeListener(markNeedsPaint);
      _scroll = w.scroll;
      if (attached) _scroll?.addListener(markNeedsPaint);
    }
    if (_borderRadius == w.borderRadius &&
        _edge == w.edge &&
        _blur == w.blur &&
        _saturation == w.saturation &&
        _band == w.band &&
        _displacement == w.displacement &&
        _decor == w.decor) {
      return;
    }
    _borderRadius = w.borderRadius;
    _edge = w.edge;
    _blur = w.blur;
    _saturation = w.saturation;
    _band = w.band;
    _displacement = w.displacement;
    _decor = w.decor;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _source?.addListener(markNeedsPaint);
    _scroll?.addListener(markNeedsPaint);
    _WallpaperGlassTracker.add(this);
  }

  @override
  void detach() {
    _source?.removeListener(markNeedsPaint);
    _scroll?.removeListener(markNeedsPaint);
    _WallpaperGlassTracker.remove(this);
    super.detach();
  }

  @override
  void dispose() {
    _clipLayer.layer = null;
    _shader?.dispose();
    super.dispose();
  }

  /// 自身左上角在页面（壁纸铺放区域）里的位置；不在该页面下时为 null。
  Offset? _originIn(RenderBox anchor) {
    if (!anchor.attached) return null;
    for (RenderObject? node = parent; node != null; node = node.parent) {
      if (identical(node, anchor)) {
        return MatrixUtils.transformPoint(getTransformTo(anchor), Offset.zero);
      }
    }
    return null;
  }

  /// 滚动以外的移动（列表插入、布局变化）不会触发重画，每帧末尾检查一次。
  void _checkMotion() {
    final painted = _paintedOrigin;
    final anchor = _source?.anchor;
    if (!attached || !hasSize || painted == null || anchor == null) return;
    if (_originIn(anchor) != painted) markNeedsPaint();
  }

  /// 画布坐标加上它就是页面坐标；纯色背景不需要对位，返回零。
  Offset? _shift(GlassBackdropSource source, Offset offset) {
    _paintedOrigin = null;
    if (source.solid != null) return Offset.zero;
    final anchor = source.anchor;
    final origin = anchor == null ? null : _originIn(anchor);
    if (origin == null) return null;
    _paintedOrigin = origin;
    return origin - offset;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final source = _source!;
    final rect = offset & size;
    final rrect = _borderRadius.toRRect(rect);
    final image = source.image;
    final shift = _shift(source, offset);
    final decor = _decor;

    if (image != null && shift != null && decor != null) {
      final refract = source.refract;
      final lens = _edge == GlassEdge.top
          ? Rect.fromLTRB(
              rect.left - 2000,
              rect.top,
              rect.right + 2000,
              rect.bottom + 2000,
            )
          : rect;
      final shader =
          _shader ??= LiquidGlassShader._imageProgram!.fragmentShader();
      shader
        ..setFloat(0, image.width.toDouble())
        ..setFloat(1, image.height.toDouble())
        ..setFloat(2, lens.left)
        ..setFloat(3, lens.top)
        ..setFloat(4, lens.width)
        ..setFloat(5, lens.height)
        ..setFloat(6, _edge == GlassEdge.top ? 0 : _borderRadius.topLeft.x)
        ..setFloat(7, math.min(_band, size.shortestSide / 2))
        // 磨砂模式的图里已经模糊、提过饱和度，着色器只负责叠装饰。
        ..setFloat(8, refract ? _displacement : 0)
        ..setFloat(9, refract ? _blur : 0)
        ..setFloat(10, refract ? _saturation : 1)
        ..setFloat(11, shift.dx)
        ..setFloat(12, shift.dy)
        ..setFloat(13, source.scale)
        ..setFloat(14, rect.left)
        ..setFloat(15, rect.top)
        ..setFloat(16, rect.width)
        ..setFloat(17, rect.height)
        ..setFloat(18, decor.tint.r)
        ..setFloat(19, decor.tint.g)
        ..setFloat(20, decor.tint.b)
        ..setFloat(21, decor.tintTop)
        ..setFloat(22, decor.tintBottom)
        ..setFloat(23, decor.specularTop)
        ..setFloat(24, decor.specularBottom)
        ..setFloat(25, decor.glow)
        ..setImageSampler(0, image, filterQuality: FilterQuality.low);
      context.canvas.drawRRect(rrect, Paint()..shader = shader);
    } else if (image != null && shift != null) {
      context.canvas.drawRRect(
        rrect,
        Paint()
          ..shader = ImageShader(
            image,
            TileMode.clamp,
            TileMode.clamp,
            // 图片像素 → 画布：先缩放到逻辑像素，再平移回画布坐标。
            (Matrix4.diagonal3Values(1 / source.scale, 1 / source.scale, 1)
                  ..setTranslationRaw(-shift.dx, -shift.dy, 0))
                .storage,
            filterQuality: FilterQuality.low,
          ),
      );
    } else if (decor != null) {
      // 壁纸图还没画好（启动后头一两帧）：先只铺玻璃底色，免得卡片完全透明。
      context.canvas.drawRRect(
        rrect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              decor.tint.withValues(alpha: decor.tintTop),
              decor.tint.withValues(alpha: decor.tintBottom),
            ],
          ).createShader(rect),
      );
    }

    final bounds = Offset.zero & size;
    _clipLayer.layer = context.pushClipRRect(
      needsCompositing,
      offset,
      bounds,
      _borderRadius.toRRect(bounds),
      super.paint,
      oldLayer: _clipLayer.layer,
    );
  }
}

abstract final class _WallpaperGlassTracker {
  static final _objects = <_RenderWallpaperGlass>{};
  static bool _registered = false;

  static void add(_RenderWallpaperGlass object) {
    _objects.add(object);
    if (_registered) return;
    _registered = true;
    SchedulerBinding.instance.addPersistentFrameCallback((_) {
      if (_objects.isEmpty) return;
      for (final object in _objects.toList(growable: false)) {
        object._checkMotion();
      }
    });
  }

  static void remove(_RenderWallpaperGlass object) => _objects.remove(object);
}

/// 顶栏玻璃背景，作为 AppBar / SliverAppBar 的 `flexibleSpace` 使用。
///
/// 玻璃模式下画成悬浮胶囊（左右留 12、上下留 4），内容从胶囊四周和后面
/// 滚过；关闭玻璃时恢复为普通通栏背景。
///
/// `SliverAppBar.large` 传入 `flexibleSpace` 后会丢掉自带的展开大标题，
/// 所以 [GlassAppBarBackground.large] 接管大标题：根据
/// [FlexibleSpaceBarSettings] 的折叠进度在展开区域底部绘制同样的标题。
class GlassAppBarBackground extends StatelessWidget {
  final Widget? largeTitle;

  const GlassAppBarBackground({super.key}) : largeTitle = null;

  const GlassAppBarBackground.large({super.key, required Widget title})
      : largeTitle = title;

  /// 胶囊离屏幕左右边缘的距离；AppBar 主题据此内缩标题和按钮。
  static const double horizontalInset = 12;

  @override
  Widget build(BuildContext context) {
    final style = GlassStyle.of(context);
    final Widget background;
    if (style.enabled) {
      final top = MediaQuery.paddingOf(context).top;
      background = Padding(
        padding: EdgeInsets.fromLTRB(
          horizontalInset,
          top + 4,
          horizontalInset,
          4,
        ),
        child: const LiquidGlass(
          borderRadius: BorderRadius.all(Radius.circular(28)),
          elevated: true,
          child: SizedBox.expand(),
        ),
      );
    } else {
      background = ColoredBox(color: Theme.of(context).colorScheme.surface);
    }

    final title = largeTitle;
    final settings =
        context.dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>();
    if (title == null || settings == null) return background;

    final textStyle = AppBarTheme.of(context).titleTextStyle ??
        Theme.of(context).textTheme.headlineSmall;
    final start = style.enabled ? horizontalInset + 16.0 : 16.0;
    return Stack(
      fit: StackFit.expand,
      children: [
        background,
        MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.34,
          child: Column(
            children: [
              SizedBox(height: settings.minExtent),
              Flexible(
                child: ClipRect(
                  child: Align(
                    alignment: AlignmentDirectional.bottomStart,
                    child: Padding(
                      padding: EdgeInsetsDirectional.fromSTEB(
                        start,
                        0,
                        start,
                        28,
                      ),
                      child: DefaultTextStyle(
                        style: textStyle ?? const TextStyle(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        child: title,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 底栏条目。
class GlassTabItem {
  final Widget icon;
  final Widget selectedIcon;
  final String label;

  const GlassTabItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}

/// 悬浮液态玻璃胶囊底栏：灰色胶囊选中指示器整块覆盖图标和文字，
/// 切换时带一点回弹滑过去。
class GlassTabBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<GlassTabItem> items;

  const GlassTabBar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.items,
  });

  static const double height = 72;
  static const _radius = BorderRadius.all(Radius.circular(36));
  static const _pad = 6.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final ink = theme.colorScheme.onSurface;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(14, 0, 14, bottomInset + 12),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SizedBox(
            height: height,
            child: LiquidGlass(
              borderRadius: _radius,
              elevated: true,
              child: Padding(
                padding: const EdgeInsets.all(_pad),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final itemWidth = constraints.maxWidth / items.length;
                    return Stack(
                      children: [
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 450),
                          curve: const Cubic(0.3, 1.4, 0.4, 1),
                          left: itemWidth * selectedIndex,
                          top: 0,
                          bottom: 0,
                          width: itemWidth,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.12)
                                  : Colors.black.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            for (var i = 0; i < items.length; i++)
                              Expanded(
                                child: _GlassTab(
                                  item: items[i],
                                  selected: i == selectedIndex,
                                  color: ink,
                                  onTap: () => onSelected(i),
                                ),
                              ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassTab extends StatelessWidget {
  final GlassTabItem item;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _GlassTab({
    required this.item,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(30),
        splashColor: Colors.transparent,
        highlightColor: color.withValues(alpha: 0.04),
        child: IconTheme.merge(
          data: IconThemeData(color: color, size: 25),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              selected ? item.selectedIcon : item.icon,
              const SizedBox(height: 3),
              Text(
                item.label,
                maxLines: 1,
                style: TextStyle(
                  color: color,
                  fontSize: 12.5,
                  height: 1.2,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 布局完成后回报子组件尺寸，用于给浮在内容上的玻璃栏预留空间。
class SizeReporter extends SingleChildRenderObjectWidget {
  final ValueChanged<Size> onChanged;

  const SizeReporter({super.key, required this.onChanged, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderSizeReporter(onChanged);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderSizeReporter renderObject,
  ) {
    renderObject.onChanged = onChanged;
  }
}

class RenderSizeReporter extends RenderProxyBox {
  RenderSizeReporter(this.onChanged);

  ValueChanged<Size> onChanged;
  Size? _lastSize;

  @override
  void performLayout() {
    super.performLayout();
    if (size == _lastSize) return;
    _lastSize = size;
    final reported = size;
    WidgetsBinding.instance.addPostFrameCallback((_) => onChanged(reported));
  }
}
