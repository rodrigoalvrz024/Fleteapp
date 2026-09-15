import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_theme.dart';
import '../providers/auth_provider.dart';

class MuvvBackButton extends ConsumerWidget {
  final String? fallbackPath;

  const MuvvBackButton({super.key, this.fallbackPath});

  @override
  Widget build(BuildContext context, WidgetRef ref) => BackButton(
        onPressed: () {
          if (context.canPop()) {
            context.pop();
          } else {
            final role = ref.read(authProvider).user?.role;
            context.go(fallbackPath ??
                switch (role) {
                  'driver' => '/app/driver',
                  'admin' => '/admin',
                  _ => '/app/client',
                });
          }
        },
      );
}

/// A single compact header and safe content area for mobile task screens.
class MuvvPageScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? leading;
  final List<Widget> actions;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final String? fallbackPath;

  const MuvvPageScaffold({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.leading,
    this.actions = const [],
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.fallbackPath,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          leading: leading ?? MuvvBackButton(fallbackPath: fallbackPath),
          titleSpacing: 0,
          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: actions,
        ),
        body: SafeArea(
          top: false,
          bottom: bottomNavigationBar == null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Text(subtitle!,
                      style: Theme.of(context).textTheme.bodySmall),
                ),
              Expanded(child: child),
            ],
          ),
        ),
        bottomNavigationBar: bottomNavigationBar,
        floatingActionButton: floatingActionButton,
        floatingActionButtonLocation: floatingActionButtonLocation,
      );
}
