import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeService extends ChangeNotifier {
  ThemeService._();
  static final ThemeService instance = ThemeService._();

  static const _key = 'theme_mode';
  static const _textScaleKey = 'text_scale';
  static const _customFontPathKey = 'custom_font_path';
  static const _customFontNameKey = 'custom_font_name';
  static const _customFontFamilyKey = 'custom_font_family';
  static const _glassEnabledKey = 'glass_enabled';
  static const _refractionEnabledKey = 'glass_refraction_enabled';
  static const _wallpaperKey = 'wallpaper_id';
  static const _wallpaperDimKey = 'wallpaper_dim';
  static const _customWallpapersKey = 'custom_wallpapers';

  /// 壁纸 id 前缀：内置渐变壁纸 / 用户导入的图片。
  static const presetWallpaperPrefix = 'preset:';
  static const fileWallpaperPrefix = 'file:';

  static const _maxCustomWallpapers = 12;

  ThemeMode _mode = ThemeMode.system;
  double _textScale = 1.0;
  String? _customFontPath;
  String? _customFontName;
  String? _customFontFamily;
  bool _glassEnabled = true;
  bool _refractionEnabled = true;
  String? _wallpaperId;
  double _wallpaperDim = 0.35;
  List<String> _customWallpapers = const [];

  ThemeMode get mode => _mode;
  bool get isDark => _mode == ThemeMode.dark;
  double get textScale => _textScale;
  bool get hasCustomFont => _customFontFamily != null;
  String? get customFontName => _customFontName;
  String? get customFontFamily => _customFontFamily;

  /// 顶栏 / 底栏 / 评论区是否使用液态玻璃（背景模糊）效果。
  bool get glassEnabled => _glassEnabled;

  /// 玻璃边缘的透镜折射（需要设备支持 Impeller 着色器，否则自动用磨砂）。
  bool get refractionEnabled => _refractionEnabled;

  /// 当前壁纸：`null` 表示不使用壁纸，否则为 `preset:<id>` 或 `file:<path>`。
  String? get wallpaperId => _wallpaperId;
  bool get hasWallpaper => _wallpaperId != null;

  /// 壁纸上叠加的表面色遮罩不透明度，保证文字可读。
  double get wallpaperDim => _wallpaperDim;

  /// 用户导入过的壁纸图片路径（最新的在前）。
  List<String> get customWallpapers => _customWallpapers;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final savedScale = prefs.getDouble(_textScaleKey);
    if (savedScale != null) {
      _textScale = savedScale.clamp(0.85, 1.25).toDouble();
    }

    switch (prefs.getString(_key)) {
      case 'light':
        _mode = ThemeMode.light;
        break;
      case 'dark':
        _mode = ThemeMode.dark;
        break;
      default:
        _mode = ThemeMode.system;
    }

    _glassEnabled = prefs.getBool(_glassEnabledKey) ?? true;
    _refractionEnabled = prefs.getBool(_refractionEnabledKey) ?? true;
    _wallpaperDim =
        (prefs.getDouble(_wallpaperDimKey) ?? _wallpaperDim).clamp(0.0, 0.85);
    final customWallpapers = <String>[];
    for (final path in prefs.getStringList(_customWallpapersKey) ?? const []) {
      if (await File(path).exists()) customWallpapers.add(path);
    }
    _customWallpapers = List.unmodifiable(customWallpapers);
    final wallpaper = prefs.getString(_wallpaperKey);
    if (wallpaper != null &&
        (!wallpaper.startsWith(fileWallpaperPrefix) ||
            customWallpapers.contains(
              wallpaper.substring(fileWallpaperPrefix.length),
            ))) {
      _wallpaperId = wallpaper;
    }

    final fontPath = prefs.getString(_customFontPathKey);
    final fontName = prefs.getString(_customFontNameKey);
    final fontFamily = prefs.getString(_customFontFamilyKey);
    if (fontPath != null && fontName != null && fontFamily != null) {
      try {
        final file = File(fontPath);
        if (!await file.exists()) {
          throw FileSystemException(
            '自定义字体文件不存在',
            fontPath,
          );
        }
        await _loadFont(await file.readAsBytes(), fontFamily);
        _customFontPath = fontPath;
        _customFontName = fontName;
        _customFontFamily = fontFamily;
      } catch (_) {
        await prefs.remove(_customFontPathKey);
        await prefs.remove(_customFontNameKey);
        await prefs.remove(_customFontFamilyKey);
      }
    }
  }

  Future<void> installCustomFont(Uint8List bytes, String fileName) async {
    if (bytes.isEmpty) throw const FormatException('字体文件为空');
    final extension = fileName.toLowerCase().split('.').last;
    if (extension != 'ttf' && extension != 'otf') {
      throw const FormatException('仅支持 TTF 和 OTF 字体');
    }

    final family = 'MTForumCustomFont_${DateTime.now().microsecondsSinceEpoch}';
    await _loadFont(bytes, family);

    final directory = await getApplicationSupportDirectory();
    final file = File('${directory.path}/mtforum_custom_font.$extension');
    await file.writeAsBytes(bytes, flush: true);

    final previousPath = _customFontPath;
    _customFontPath = file.path;
    _customFontName = fileName.trim().isEmpty ? '自定义字体' : fileName.trim();
    _customFontFamily = family;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_customFontPathKey, file.path);
    await prefs.setString(_customFontNameKey, _customFontName!);
    await prefs.setString(_customFontFamilyKey, family);

    if (previousPath != null && previousPath != file.path) {
      try {
        final previous = File(previousPath);
        if (await previous.exists()) await previous.delete();
      } catch (_) {}
    }
  }

  Future<void> clearCustomFont() async {
    final path = _customFontPath;
    _customFontPath = null;
    _customFontName = null;
    _customFontFamily = null;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_customFontPathKey);
    await prefs.remove(_customFontNameKey);
    await prefs.remove(_customFontFamilyKey);

    if (path != null) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  Future<void> _loadFont(Uint8List bytes, String family) async {
    final loader = FontLoader(family);
    loader.addFont(
      Future.value(
        ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes),
      ),
    );
    await loader.load();
  }

  Future<void> setTextScale(double value) async {
    final next = value.clamp(0.85, 1.25).toDouble();
    if ((_textScale - next).abs() < 0.001) return;
    _textScale = next;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_textScaleKey, next);
  }

  Future<void> resetTextScale() => setTextScale(1.0);

  Future<void> setMode(ThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      },
    );
  }

  Future<void> setGlassEnabled(bool value) async {
    if (_glassEnabled == value) return;
    _glassEnabled = value;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_glassEnabledKey, value);
  }

  Future<void> setRefractionEnabled(bool value) async {
    if (_refractionEnabled == value) return;
    _refractionEnabled = value;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_refractionEnabledKey, value);
  }

  Future<void> setWallpaper(String? id) async {
    if (_wallpaperId == id) return;
    _wallpaperId = id;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove(_wallpaperKey);
    } else {
      await prefs.setString(_wallpaperKey, id);
    }
  }

  Future<void> setWallpaperDim(double value) async {
    final next = value.clamp(0.0, 0.85).toDouble();
    if ((_wallpaperDim - next).abs() < 0.001) return;
    _wallpaperDim = next;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_wallpaperDimKey, next);
  }

  /// 把用户选的图片复制到应用私有目录并设为当前壁纸。
  Future<void> addCustomWallpaper(Uint8List bytes, String fileName) async {
    if (bytes.isEmpty) throw const FormatException('图片文件为空');
    final dot = fileName.lastIndexOf('.');
    var extension = dot < 0 ? 'jpg' : fileName.substring(dot + 1).toLowerCase();
    if (!const {'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'heic', 'heif'}
        .contains(extension)) {
      extension = 'jpg';
    }

    final directory = Directory(
      '${(await getApplicationSupportDirectory()).path}/wallpapers',
    );
    await directory.create(recursive: true);
    final file = File(
      '${directory.path}/wallpaper_${DateTime.now().microsecondsSinceEpoch}.$extension',
    );
    await file.writeAsBytes(bytes, flush: true);

    final next = [file.path, ..._customWallpapers];
    final overflow = next.length > _maxCustomWallpapers
        ? next.sublist(_maxCustomWallpapers)
        : const <String>[];
    _customWallpapers = List.unmodifiable(next.take(_maxCustomWallpapers));
    _wallpaperId = '$fileWallpaperPrefix${file.path}';
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_customWallpapersKey, _customWallpapers);
    await prefs.setString(_wallpaperKey, _wallpaperId!);
    for (final path in overflow) {
      await _deleteQuietly(path);
    }
  }

  Future<void> removeCustomWallpaper(String path) async {
    if (!_customWallpapers.contains(path)) return;
    _customWallpapers = List.unmodifiable(
      _customWallpapers.where((item) => item != path),
    );
    final wasCurrent = _wallpaperId == '$fileWallpaperPrefix$path';
    if (wasCurrent) _wallpaperId = null;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_customWallpapersKey, _customWallpapers);
    if (wasCurrent) await prefs.remove(_wallpaperKey);
    // 先让界面不再引用这张图，再删文件，避免正在显示的图片读到空文件。
    imageCache.clear();
    await _deleteQuietly(path);
  }

  Future<void> _deleteQuietly(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
