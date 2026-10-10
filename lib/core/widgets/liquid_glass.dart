import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../theme/glass_style.dart';

/// 玻璃面板需要画高光的边。
enum GlassEdge {
  /// 整圈高光（悬浮胶囊、卡片）。
  all,

  /// 只在顶部画高光（底部弹层）。
  top,

  /// 只在底部画一条分隔细线（顶栏）。
  bottom,
}

/// 液态玻璃面板：背景模糊 + 饱和度增强 + 半透明表面色 + 边缘高光。
///
/// 模糊的是面板**后面**已经绘制的内容（滚动列表、壁纸、上一个页面），
/// 所以只有当内容真的从面板下方经过时才看得出玻璃感。
///
/// 主题里关闭玻璃效果（[GlassStyle.enabled] 为 false）时退化为不透明的
/// [fallbackColor]，不创建 BackdropFilter，低端机上没有额外开销。
class LiquidGlass extends StatelessWidget {
  final Widget? child;
  final BorderRadius borderRadius;
  final GlassEdge edge;

  /// 悬浮在内容上方的面板（底栏胶囊）加一层柔和投影。
  final bool elevated;

  /// 在主题默认不透明度上再加一点，用于承载大段文字的面板（评论区）。
  final double opacityBoost;

  /// 关闭玻璃效果时使用的颜色，默认 `surfaceContainerLow`。
  final Color? fallbackColor;

  const LiquidGlass({
    super.key,
    this.child,
    this.borderRadius = BorderRadius.zero,
    this.edge = GlassEdge.all,
    this.elevated = false,
    this.opacityBoost = 0,
    this.fallbackColor,
  });

  static final ui.ColorFilter _saturate =
      ui.ColorFilter.matrix(_saturationMatrix(1.6));

  static List<double> _saturationMatrix(double s) {
    const r = 0.2126, g = 0.7152, b = 0.0722;
    final ir = (1 - s) * r, ig = (1 - s) * g, ib = (1 - s) * b;
    return [
      ir + s, ig, ib, 0, 0, //
      ir, ig + s, ib, 0, 0, //
      ir, ig, ib + s, 0, 0, //
      0, 0, 0, 1, 0, //
    ];
  }

  @override
  Widget build(BuildContext context) {
    final style = GlassStyle.of(context);
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget panel;
    if (!style.enabled) {
      panel = CustomPaint(
        foregroundPainter: edge == GlassEdge.all
            ? _GlassRimPainter(
                borderRadius: borderRadius,
                edge: edge,
                highlight: scheme.outlineVariant,
                divider: scheme.outlineVariant,
                sheen: Colors.transparent,
              )
            : null,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: fallbackColor ?? scheme.surfaceContainerLow,
            borderRadius: borderRadius,
          ),
          child: child,
        ),
      );
    } else {
      final base = (style.tintOpacity + opacityBoost).clamp(0.0, 1.0);
      panel = BackdropFilter(
        filter: ui.ImageFilter.compose(
          outer: _saturate,
          inner: ui.ImageFilter.blur(
            sigmaX: style.blurSigma,
            sigmaY: style.blurSigma,
          ),
        ),
        child: CustomPaint(
          foregroundPainter: _GlassRimPainter(
            borderRadius: borderRadius,
            edge: edge,
            highlight: style.highlight,
            divider: scheme.outlineVariant.withValues(alpha: 0.45),
            sheen: Colors.white.withValues(alpha: isDark ? 0.05 : 0.16),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  style.tint.withValues(alpha: (base - 0.06).clamp(0.0, 1.0)),
                  style.tint.withValues(alpha: (base + 0.06).clamp(0.0, 1.0)),
                ],
              ),
            ),
            child: child,
          ),
        ),
      );
    }

    panel = borderRadius == BorderRadius.zero
        ? ClipRect(child: panel)
        : ClipRRect(borderRadius: borderRadius, child: panel);

    if (!elevated) return panel;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.07),
            blurRadius: 24,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: panel,
    );
  }
}

/// 绘制玻璃的高光边、顶部光泽和底部分隔线。
class _GlassRimPainter extends CustomPainter {
  final BorderRadius borderRadius;
  final GlassEdge edge;
  final Color highlight;
  final Color divider;
  final Color sheen;

  const _GlassRimPainter({
    required this.borderRadius,
    required this.edge,
    required this.highlight,
    required this.divider,
    required this.sheen,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    if (rect.isEmpty) return;

    // 顶部一抹柔光，模拟光线照在玻璃表面的反射。
    if (sheen.a > 0) {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [sheen, sheen.withValues(alpha: 0)],
            stops: const [0, 0.55],
          ).createShader(rect),
      );
    }

    switch (edge) {
      case GlassEdge.bottom:
        canvas.drawLine(
          Offset(0, size.height - 0.5),
          Offset(size.width, size.height - 0.5),
          Paint()
            ..color = divider
            ..strokeWidth = 1,
        );
      case GlassEdge.top:
        final rim = borderRadius.toRRect(rect.deflate(0.5));
        canvas.drawRRect(
          rim,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [highlight, highlight.withValues(alpha: 0)],
              stops: const [0, 0.12],
            ).createShader(rect),
        );
      case GlassEdge.all:
        final rim = borderRadius.toRRect(rect.deflate(0.5));
        canvas.drawRRect(
          rim,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..shader = LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                highlight,
                highlight.withValues(alpha: highlight.a * 0.18),
                highlight.withValues(alpha: highlight.a * 0.08),
                highlight.withValues(alpha: highlight.a * 0.55),
              ],
              stops: const [0, 0.38, 0.62, 1],
            ).createShader(rect),
        );
    }
  }

  @override
  bool shouldRepaint(_GlassRimPainter oldDelegate) {
    return oldDelegate.borderRadius != borderRadius ||
        oldDelegate.edge != edge ||
        oldDelegate.highlight != highlight ||
        oldDelegate.divider != divider ||
        oldDelegate.sheen != sheen;
  }
}

/// 顶栏玻璃背景，作为 AppBar / SliverAppBar 的 `flexibleSpace` 使用。
///
/// `SliverAppBar.large` 传入 `flexibleSpace` 后会丢掉自带的展开大标题，
/// 所以这里可选地接管大标题：根据 [FlexibleSpaceBarSettings] 的折叠进度
/// 在展开区域底部绘制同样的标题。
class GlassAppBarBackground extends StatelessWidget {
  final Widget? largeTitle;

  const GlassAppBarBackground({super.key}) : largeTitle = null;

  const GlassAppBarBackground.large({super.key, required Widget title})
      : largeTitle = title;

  @override
  Widget build(BuildContext context) {
    final glass = LiquidGlass(
      edge: GlassEdge.bottom,
      fallbackColor: Theme.of(context).colorScheme.surface,
      child: const SizedBox.expand(),
    );
    final title = largeTitle;
    final settings =
        context.dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>();
    if (title == null || settings == null) return glass;

    final style = AppBarTheme.of(context).titleTextStyle ??
        Theme.of(context).textTheme.headlineSmall;
    return Stack(
      fit: StackFit.expand,
      children: [
        glass,
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
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        16,
                        0,
                        16,
                        28,
                      ),
                      child: DefaultTextStyle(
                        style: style ?? const TextStyle(),
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

/// 悬浮的液态玻璃胶囊底栏。
class GlassNavigationShell extends StatelessWidget {
  final Widget child;

  const GlassNavigationShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    const radius = BorderRadius.all(Radius.circular(30));
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottomInset + 10),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: LiquidGlass(
            borderRadius: radius,
            elevated: true,
            child: MediaQuery.removePadding(
              context: context,
              removeBottom: true,
              child: NavigationBarTheme(
                data: NavigationBarTheme.of(context).copyWith(height: 64),
                child: child,
              ),
            ),
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
