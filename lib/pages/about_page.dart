import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_version_service.dart';
import '../core/widgets/liquid_glass.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  static const _avatarUrl = 'https://avatars.githubusercontent.com/u/187751705';
  static const _authorName = '我什么也不想要了';
  static const _qq = '615192041';
  static const _email = '615162041@qq.com';
  static const _forumName = 'Cynnie';

  late final Future<Map<String, dynamic>> _versionInfoFuture;

  @override
  void initState() {
    super.initState();
    _versionInfoFuture = AppVersionService.instance.getCurrentVersionInfo();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _copy(String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label 已复制'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: const Text('关于'),
            flexibleSpace: GlassAppBarBackground.large(title: const Text('关于')),
            pinned: true,
            centerTitle: true,
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  _buildAppHeader(theme, colors),
                  const SizedBox(height: 28),
                  const _SectionTitle(title: '作者信息'),
                  const SizedBox(height: 10),
                  _buildAuthorCard(theme, colors),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppHeader(ThemeData theme, ColorScheme colors) {
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colors.primary,
                colors.primary.withValues(alpha: 0.72),
              ],
            ),
          ),
          child: const Icon(
            Icons.forum_rounded,
            size: 40,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'MT论坛',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        FutureBuilder<Map<String, dynamic>>(
          future: _versionInfoFuture,
          builder: (context, snapshot) {
            final versionName = '${snapshot.data?['versionName'] ?? ''}'.trim();
            return Text(
              versionName.isEmpty ? 'v—' : 'v$versionName',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.outline,
              ),
            );
          },
        ),
        const SizedBox(height: 3),
        Text(
          'MT论坛第三方客户端',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.outline,
          ),
        ),
      ],
    );
  }

  Widget _buildAuthorCard(ThemeData theme, ColorScheme colors) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
        child: Column(
          children: [
            Container(
              width: 104,
              height: 104,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.primaryContainer,
              ),
              child: ClipOval(
                child: Image.network(
                  _avatarUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => ColoredBox(
                    color: colors.surfaceContainerHighest,
                    child: Icon(
                      Icons.person_rounded,
                      size: 48,
                      color: colors.primary,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              _authorName,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
              decoration: BoxDecoration(
                color: colors.secondaryContainer,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'MT论坛 · $_forumName',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.onSecondaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Divider(color: colors.outlineVariant.withValues(alpha: 0.65)),
            _ContactRow(
              icon: Icons.chat_bubble_outline_rounded,
              label: 'QQ',
              value: _qq,
              onCopy: () => _copy('QQ', _qq),
            ),
            _ContactRow(
              icon: Icons.mail_outline_rounded,
              label: 'Email',
              value: _email,
              onCopy: () => _copy('邮箱', _email),
            ),
            _ContactRow(
              icon: Icons.forum_outlined,
              label: 'MT论坛',
              value: _forumName,
              onCopy: () => _copy('论坛用户名', _forumName),
            ),
            const SizedBox(height: 10),
            Divider(color: colors.outlineVariant.withValues(alpha: 0.65)),
            const SizedBox(height: 12),
            Text(
              '技能',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            const _SkillBar(label: 'C++', percent: 56),
            const SizedBox(height: 12),
            const _SkillBar(label: 'Shell', percent: 16),
            const SizedBox(height: 12),
            const _SkillBar(label: 'Python', percent: 7),
            const SizedBox(height: 12),
            const _SkillBar(label: 'Java', percent: 3),
          ],
        ),
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onCopy;

  const _ContactRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onCopy,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colors.primaryContainer.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(11),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 19, color: colors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colors.outline,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      value,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.content_copy_rounded,
                size: 18,
                color: colors.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SkillBar extends StatelessWidget {
  final String label;
  final int percent;

  const _SkillBar({required this.label, required this.percent});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              '$percent%',
              style: theme.textTheme.labelLarge?.copyWith(
                color: colors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: percent / 100,
            minHeight: 8,
            backgroundColor: colors.surfaceContainerHighest,
            color: colors.primary,
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        title,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
