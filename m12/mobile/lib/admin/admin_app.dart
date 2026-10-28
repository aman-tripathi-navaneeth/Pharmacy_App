import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app/theme.dart';
import 'admin_shell.dart';

GoRouter buildAdminRouter() => GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const AdminShell()),
        GoRoute(path: '/tickets/:id', builder: (_, s) => AdminShell(selectedId: s.pathParameters['id'])),
      ],
    );

/// Platform support console (web). Separate from the shop app, same code base.
class SupportConsoleApp extends StatefulWidget {
  const SupportConsoleApp({super.key});

  @override
  State<SupportConsoleApp> createState() => _SupportConsoleAppState();
}

class _SupportConsoleAppState extends State<SupportConsoleApp> {
  final _router = buildAdminRouter();

  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: 'Support Console · Medical Store',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        routerConfig: _router,
      );
}
