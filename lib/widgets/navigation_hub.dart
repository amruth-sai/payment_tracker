import 'package:flutter/material.dart';

class HubLink {
  const HubLink({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
}

class HubSection {
  const HubSection(this.title, this.links);
  final String title;
  final List<HubLink> links;
}

/// A navigation-only surface: every row opens an existing feature screen.
class NavigationHub extends StatelessWidget {
  const NavigationHub({
    super.key,
    required this.title,
    required this.description,
    required this.sections,
    required this.onOpenSettings,
  });
  final String title;
  final String description;
  final List<HubSection> sections;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: onOpenSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: ListView(
        key: PageStorageKey('hub-$title'),
        primary: false,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            description,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          for (final section in sections) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(section.title, style: theme.textTheme.titleSmall),
            ),
            Card(
              elevation: 0,
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              color: theme.colorScheme.surfaceContainerLow,
              child: Column(
                children: [
                  for (var i = 0; i < section.links.length; i++) ...[
                    if (i > 0) const Divider(height: 1, indent: 72),
                    ListTile(
                      key: ValueKey('destination-${section.links[i].id}'),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          section.links[i].icon,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                      title: Text(
                        section.links[i].title,
                        style: theme.textTheme.titleSmall,
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(section.links[i].subtitle),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: section.links[i].onTap,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ],
      ),
    );
  }
}
