import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import '../core/data/workspace.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/app_widgets.dart';
import '../features/shell/presentation/app_shell.dart';

class QingLuanApp extends StatelessWidget {
  const QingLuanApp({super.key, required this.store});
  final Workspace store;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) => CupertinoApp(
      title: '青鸾考勤',
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      localizationsDelegates: const [
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      debugShowCheckedModeBanner: false,
      theme: switch (store.settings['theme']) {
        'light' => AppTheme.light,
        'dark' => AppTheme.dark,
        _ => AppTheme.system,
      },
      builder: (context, child) =>
          GlassScope(enabled: store.settings['glass'] != false, child: child!),
      home: AppShell(store: store),
    ),
  );
}
