import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/theme/wallpapers.dart';
import '../core/widgets/liquid_glass.dart';
import '../services/theme_service.dart';

/// 背景壁纸：无壁纸 / 内置渐变 / 相册导入，外加遮罩强度和玻璃效果开关。
class WallpaperPage extends StatefulWidget {
  const WallpaperPage({super.key});

  @override
  State<WallpaperPage> createState() => _WallpaperPageState();
}

class _WallpaperPageState extends State<WallpaperPage> {
  final _theme = ThemeService.instance;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _theme.addListener(_refresh);
  }

  @override
  void dispose() {
    _theme.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _importImage() async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (file == null) return;
      await _theme.addCustomWallpaper(await file.readAsBytes(), file.name);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已设为壁纸')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入壁纸失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _confirmRemove(String path) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这张壁纸？'),
        content: const Text('只会删除应用内保存的副本，不影响相册里的原图。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) await _theme.removeCustomWallpaper(path);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final current = _theme.wallpaperId;

    final tiles = <Widget>[
      _WallpaperTile(
        label: '无壁纸',
        selected: current == null,
        onTap: () => _theme.setWallpaper(null),
        child: ColoredBox(
          color: colors.surface,
          child: Icon(Icons.block_rounded, color: colors.outline),
        ),
      ),
      _WallpaperTile(
        label: _importing ? '导入中…' : '从相册选择',
        selected: false,
        onTap: _importing ? null : _importImage,
        child: ColoredBox(
          color: colors.surfaceContainerHigh,
          child: _importing
              ? const Center(
                  child: SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : Icon(Icons.add_photo_alternate_outlined, color: colors.primary),
        ),
      ),
      for (final path in _theme.customWallpapers)
        _WallpaperTile(
          label: '我的图片',
          selected: current == '${ThemeService.fileWallpaperPrefix}$path',
          onTap: () =>
              _theme.setWallpaper('${ThemeService.fileWallpaperPrefix}$path'),
          onLongPress: () => _confirmRemove(path),
          child: WallpaperView(
            id: '${ThemeService.fileWallpaperPrefix}$path',
            decodeHeight: 480,
          ),
        ),
      for (final preset in wallpaperPresets)
        _WallpaperTile(
          label: preset.name,
          selected: current == preset.id,
          onTap: () => _theme.setWallpaper(preset.id),
          child: WallpaperView(id: preset.id),
        ),
    ];

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const SliverAppBar(
            flexibleSpace: GlassAppBarBackground(),
            title: Text('背景壁纸'),
            pinned: true,
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Card(
                child: Column(
                  children: [
                    SwitchListTile(
                      secondary: const Icon(Icons.blur_on_rounded),
                      title: const Text('液态玻璃效果'),
                      subtitle: const Text('顶栏、底栏和评论区背景模糊，关闭可降低耗电'),
                      value: _theme.glassEnabled,
                      onChanged: _theme.setGlassEnabled,
                    ),
                    if (current != null) ...[
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 12, 4),
                        child: Row(
                          children: [
                            const Icon(Icons.contrast_rounded),
                            const SizedBox(width: 16),
                            const Expanded(
                              child: Text(
                                '壁纸遮罩',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                            Text(
                              '${(_theme.wallpaperDim * 100).round()}%',
                              style: TextStyle(
                                color: colors.primary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(38, 0, 14, 4),
                        child: Slider(
                          value: _theme.wallpaperDim,
                          min: 0,
                          max: 0.85,
                          divisions: 17,
                          label: '${(_theme.wallpaperDim * 100).round()}%',
                          onChanged: _theme.setWallpaperDim,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(56, 0, 16, 14),
                        child: Text(
                          '遮罩越高文字越清晰，壁纸越淡',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            sliver: SliverToBoxAdapter(
              child: Text(
                '长按导入的图片可删除',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              16,
              4,
              16,
              24 + MediaQuery.paddingOf(context).bottom,
            ),
            sliver: SliverGrid.count(
              crossAxisCount: 3,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.56,
              children: tiles,
            ),
          ),
        ],
      ),
    );
  }
}

class _WallpaperTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget child;

  const _WallpaperTile({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.child,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    const radius = BorderRadius.all(Radius.circular(16));
    return Column(
      children: [
        Expanded(
          child: Semantics(
            button: true,
            selected: selected,
            label: label,
            child: GestureDetector(
              onTap: onTap,
              onLongPress: onLongPress,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                decoration: BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(
                    color: selected ? colors.primary : colors.outlineVariant,
                    width: selected ? 2.5 : 1,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: const BorderRadius.all(Radius.circular(14)),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      child,
                      if (selected)
                        Align(
                          alignment: Alignment.topRight,
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: CircleAvatar(
                              radius: 11,
                              backgroundColor: colors.primary,
                              child: Icon(
                                Icons.check_rounded,
                                size: 15,
                                color: colors.onPrimary,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                color: selected ? colors.primary : colors.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}
