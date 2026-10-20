import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'app/app.dart';
import 'core/data/workspace.dart';
import 'core/storage/cos_storage.dart';
import 'core/storage/object_storage.dart';
import 'core/sync/sync_service.dart';
import 'core/widgets/app_widgets.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Draw behind the status and navigation bars so the layered backdrop is not
  // cut off by a black system bar strip.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const Bootstrap());
}

/// Reads the COS profile from settings + secure storage on demand, so keys
/// edited in settings take effect without a restart.
Future<ObjectStorage?> resolveCloudStorage(Workspace store) async {
  const secure = FlutterSecureStorage();
  return CosObjectStorage.fromSettings(
    store.settings,
    await secure.read(key: 'storage_id') ?? '',
    await secure.read(key: 'storage_key') ?? '',
    token: await secure.read(key: 'storage_token') ?? '',
  );
}

class Bootstrap extends StatefulWidget {
  const Bootstrap({super.key});
  @override
  State<Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<Bootstrap> {
  Workspace? store;
  SyncService? sync;
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
      // Write-through upload: every local save schedules one debounced upload.
      final service = SyncService(
        workspace,
        storageFactory: () => resolveCloudStorage(workspace),
      );
      workspace.sync = service;
      service.attach();
      if (mounted) {
        setState(() {
          store = workspace;
          sync = service;
        });
      }
    } catch (_) {
      await workspace.close();
      if (mounted) setState(() => error = '无法打开本地数据，请检查磁盘空间和系统权限后重试。');
    }
  }

  @override
  void dispose() {
    sync?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => store != null
      ? QingLuanApp(store: store!)
      : CupertinoApp(
          home: CupertinoPageScaffold(
            child: error == null
                ? const SyncSkeletonPage()
                : Center(
                    child: Column(
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
