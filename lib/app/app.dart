import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import '../core/data/workspace.dart';
import '../core/theme/app_theme.dart';
import '../features/shell/presentation/app_shell.dart';

class QingLuanApp extends StatelessWidget {
  const QingLuanApp({super.key, required this.store});
  final Workspace store;
  @override
  Widget build(BuildContext context) => CupertinoApp(
    title: '青鸾考勤',
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
    localizationsDelegates: const [
      GlobalCupertinoLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    debugShowCheckedModeBanner: false,
    theme: AppTheme.system,
    home: AppShell(store: store),
  );
}
