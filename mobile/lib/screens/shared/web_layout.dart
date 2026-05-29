import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class WebPageScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget> actions;
  final Widget? floatingActionButton;

  const WebPageScaffold({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.actions = const [],
    this.floatingActionButton,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        titleSpacing: 20,
        title: _AppBarTitle(title: title, subtitle: subtitle),
        actions: actions,
      ),
      body: SafeArea(child: child),
      floatingActionButton: floatingActionButton,
    );
  }
}

class WebPageBody extends StatelessWidget {
  final List<Widget> children;
  final Future<void> Function()? onRefresh;
  final EdgeInsetsGeometry padding;
  final double maxWidth;

  const WebPageBody({
    super.key,
    required this.children,
    this.onRefresh,
    this.padding = const EdgeInsets.fromLTRB(20, 20, 20, 40),
    this.maxWidth = 960,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(maxWidth, constraints.maxWidth);
        final scrollable = Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: width,
            height: constraints.maxHeight,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: padding,
              children: children,
            ),
          ),
        );

        if (onRefresh == null) return scrollable;

        return RefreshIndicator(
          color: AppTheme.primary,
          onRefresh: onRefresh!,
          child: scrollable,
        );
      },
    );
  }
}

class WebLoadingState extends StatelessWidget {
  const WebLoadingState({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: AppTheme.primary,
      ),
    );
  }
}

class WebEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final String? actionLabel;
  final VoidCallback? onAction;

  const WebEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: AppTheme.cardDecoration(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, size: 30, color: AppTheme.primary),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppTheme.midnight,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                description,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppTheme.slate600,
                  height: 1.45,
                ),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: onAction,
                  child: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class WebPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const WebPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: AppTheme.cardDecoration(),
      child: child,
    );
  }
}

class _AppBarTitle extends StatelessWidget {
  final String title;
  final String? subtitle;

  const _AppBarTitle({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppTheme.slate400,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}
