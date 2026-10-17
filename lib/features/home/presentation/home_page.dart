import 'package:flutter/cupertino.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});
  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    child: SafeArea(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(CupertinoIcons.calendar, size: 48),
            const SizedBox(height: 16),
            Text(
              '基础工程已就绪',
              style: CupertinoTheme.of(context).textTheme.navTitleTextStyle,
            ),
            const SizedBox(height: 8),
            const Text('考勤、同步与冲突处理模块将在此基础上接入。'),
          ],
        ),
      ),
    ),
  );
}
