import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import '../core/data/workspace.dart';
import '../core/reminders/notice_service.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/app_widgets.dart';
import '../features/shell/presentation/app_shell.dart';

class QingLuanApp extends StatelessWidget {
  const QingLuanApp({super.key, required this.store, this.noticeSource});
  final Workspace store;
  final NoticeSource? noticeSource;
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
      builder: (context, child) {
        final dark = switch (store.settings['theme']) {
          'dark' => true,
          'light' => false,
          _ =>
            MediaQuery.platformBrightnessOf(context) == Brightness.dark,
        };
        return GlassScope(
          enabled: store.settings['glass'] != false,
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle(
              statusBarColor: const Color(0x00000000),
              statusBarIconBrightness: dark
                  ? Brightness.light
                  : Brightness.dark,
              systemNavigationBarColor: const Color(0x00000000),
              systemNavigationBarDividerColor: const Color(0x00000000),
              systemNavigationBarIconBrightness: dark
                  ? Brightness.light
                  : Brightness.dark,
            ),
            child: child!,
          ),
        );
      },
      home: AppShell(store: store, noticeSource: noticeSource),
    ),
  );
}
