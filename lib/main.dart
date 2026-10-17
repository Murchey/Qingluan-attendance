import 'package:flutter/cupertino.dart';
import 'app/app.dart';
import 'core/data/workspace.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const Bootstrap());
}

class Bootstrap extends StatefulWidget {
  const Bootstrap({super.key});
  @override
  State<Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<Bootstrap> {
  Workspace? store;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() => error = null);
    final workspace = Workspace.memory();
    try {
      await workspace.open();
      if (mounted) setState(() => store = workspace);
    } catch (_) {
      await workspace.close();
      if (mounted) setState(() => error = '无法打开本地数据，请检查磁盘空间和系统权限后重试。');
    }
  }

  @override
  Widget build(BuildContext context) => store != null
      ? QingLuanApp(store: store!)
      : CupertinoApp(
          home: CupertinoPageScaffold(
            child: Center(
              child: error == null
                  ? const CupertinoActivityIndicator()
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(error!),
                        CupertinoButton(
                          onPressed: load,
                          child: const Text('重试'),
                        ),
                      ],
                    ),
            ),
          ),
        );
}
