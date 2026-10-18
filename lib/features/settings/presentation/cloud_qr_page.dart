import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/config/bucket_address.dart';
import '../../../core/data/workspace.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/ui.dart';

const _qrType = 'qingluan-cloud-config';

Map<String, dynamic> _configPayload(
  Workspace store,
  Map<String, String> secrets,
) {
  final provider = (store.settings['provider'] ?? 'COS').toString();
  return {
    'type': _qrType,
    'version': 1,
    'provider': provider,
    'url': BucketAddress.configuredUrl(store.settings, provider),
    'endpoint': (store.settings['endpoint'] ?? '').toString(),
    'bucket': (store.settings['bucket'] ?? '').toString(),
    'accessKeyId': secrets['storage_id'] ?? '',
    'secretAccessKey': secrets['storage_key'] ?? '',
    'securityToken': secrets['storage_token'] ?? '',
    'autoUpload': store.settings['autoUpload'] != false,
  };
}

Future<void> showCloudQrPage(BuildContext context, Workspace store) =>
    Navigator.of(
      context,
    ).push(CupertinoPageRoute<void>(builder: (_) => CloudQrPage(store: store)));

class CloudQrPage extends StatefulWidget {
  const CloudQrPage({super.key, required this.store});
  final Workspace store;

  @override
  State<CloudQrPage> createState() => _CloudQrPageState();
}

class _CloudQrPageState extends State<CloudQrPage> {
  final secure = const FlutterSecureStorage();
  final picker = ImagePicker();
  final scanner = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  bool busy = false;

  @override
  void dispose() {
    scanner.dispose();
    super.dispose();
  }

  Future<Map<String, String>> _secrets() async => {
    'storage_id': await secure.read(key: 'storage_id') ?? '',
    'storage_key': await secure.read(key: 'storage_key') ?? '',
    'storage_token': await secure.read(key: 'storage_token') ?? '',
  };

  Future<void> _generate() async {
    final secrets = await _secrets();
    final payload = jsonEncode(_configPayload(widget.store, secrets));
    if (!mounted) return;
    final accepted = await confirm(
      context,
      '生成云存储二维码？',
      '二维码包含存储地址和密钥。请只分享给可信管理员，不要发布到公开群聊。',
    );
    if (!accepted || !mounted) return;
    await Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => CloudQrPreviewPage(payload: payload),
      ),
    );
  }

  Future<void> _pickImage() async {
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null || !mounted) return;
    setState(() => busy = true);
    try {
      final result = await scanner.analyzeImage(image.path);
      final value = result?.barcodes
          .map((barcode) => barcode.rawValue)
          .whereType<String>()
          .firstOrNull;
      if (value == null) {
        throw const FormatException('图片中没有识别到二维码');
      }
      await _apply(value);
    } catch (e) {
      if (mounted) await message(context, '读取二维码失败', '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _apply(String raw) async {
    final decoded = jsonDecode(raw);
    if (decoded is! Map || decoded['type'] != _qrType) {
      throw const FormatException('这不是青鸾考勤云存储配置二维码');
    }
    final provider = decoded['provider']?.toString() ?? '';
    if (!{'COS', 'OSS', 'S3'}.contains(provider)) {
      throw const FormatException('二维码中的存储服务类型无效');
    }
    final secrets = <String, String>{
      'storage_id': decoded['accessKeyId']?.toString() ?? '',
      'storage_key': decoded['secretAccessKey']?.toString() ?? '',
      'storage_token': decoded['securityToken']?.toString() ?? '',
    };
    widget.store.settings['provider'] = provider;
    if (provider == 'COS' || provider == 'OSS') {
      widget.store.settings[BucketAddress.settingKey(provider)] =
          decoded['url']?.toString() ?? '';
    } else {
      widget.store.settings['endpoint'] = decoded['endpoint']?.toString() ?? '';
      widget.store.settings['bucket'] = decoded['bucket']?.toString() ?? '';
    }
    widget.store.settings['autoUpload'] = decoded['autoUpload'] != false;
    await secure.write(key: 'storage_id', value: secrets['storage_id']);
    await secure.write(key: 'storage_key', value: secrets['storage_key']);
    await secure.write(key: 'storage_token', value: secrets['storage_token']);
    await widget.store.persist();
    if (mounted) {
      await message(context, '配置已导入', '已填入 $provider 存储配置和密钥。请返回设置页进行连接测试。');
    }
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: const CupertinoNavigationBar(middle: Text('二维码配置')),
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(Gap.md),
        children: [
          SettingsGroup(
            children: [
              SettingRow(
                '扫描二维码',
                detail: '打开相机扫描云存储配置',
                onTap: () => Navigator.of(context).push(
                  CupertinoPageRoute<void>(
                    builder: (_) => CloudQrScannerPage(onScanned: _apply),
                  ),
                ),
              ),
              SettingRow(
                '从相册选择二维码',
                detail: busy ? '正在识别…' : '选择截图或相册中的二维码图片',
                onTap: busy ? null : _pickImage,
              ),
              SettingRow(
                '生成我的配置二维码',
                detail: '把当前云存储地址和密钥编码成二维码',
                onTap: _generate,
              ),
            ],
          ),
          const SizedBox(height: Gap.md),
          Text(
            '二维码包含密钥，导入后会写入系统安全存储。请只在可信设备之间传递。',
            style: AppType.footnoteStyle.copyWith(
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
          ),
        ],
      ),
    ),
  );
}

class CloudQrScannerPage extends StatefulWidget {
  const CloudQrScannerPage({super.key, required this.onScanned});
  final Future<void> Function(String raw) onScanned;

  @override
  State<CloudQrScannerPage> createState() => _CloudQrScannerPageState();
}

class _CloudQrScannerPageState extends State<CloudQrScannerPage> {
  bool handled = false;

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (handled) return;
    final raw = capture.barcodes
        .map((b) => b.rawValue)
        .whereType<String>()
        .firstOrNull;
    if (raw == null || raw.isEmpty) return;
    handled = true;
    await widget.onScanned(raw);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: const CupertinoNavigationBar(middle: Text('扫描二维码')),
    child: Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(onDetect: _onDetect),
        Center(
          child: Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              border: Border.all(color: CupertinoColors.white, width: 3),
              borderRadius: BorderRadius.circular(Radii.card),
            ),
          ),
        ),
        Positioned(
          left: Gap.md,
          right: Gap.md,
          bottom: Gap.lg,
          child: Text(
            '将二维码放入框内，识别后会自动填入云存储配置',
            textAlign: TextAlign.center,
            style: AppType.button.copyWith(color: CupertinoColors.white),
          ),
        ),
      ],
    ),
  );
}

class CloudQrPreviewPage extends StatefulWidget {
  const CloudQrPreviewPage({super.key, required this.payload});
  final String payload;

  @override
  State<CloudQrPreviewPage> createState() => _CloudQrPreviewPageState();
}

class _CloudQrPreviewPageState extends State<CloudQrPreviewPage> {
  bool saving = false;

  Future<Uint8List?> _bytes() async {
    final painter = QrPainter(
      data: widget.payload,
      version: QrVersions.auto,
      errorCorrectionLevel: QrErrorCorrectLevel.M,
    );
    final data = await painter.toImageData(1200);
    return data?.buffer.asUint8List();
  }

  Future<void> _save() async {
    setState(() => saving = true);
    try {
      final bytes = await _bytes();
      if (bytes == null) throw const FormatException('二维码生成失败');
      if (!await Gal.requestAccess(toAlbum: true)) {
        throw const FormatException('没有获得相册写入权限');
      }
      await Gal.putImageBytes(
        bytes,
        album: '青鸾考勤',
        name: 'qingluan-cloud-config',
      );
      if (mounted) await message(context, '已保存到相册', '二维码已保存到“青鸾考勤”相册。');
    } catch (e) {
      if (mounted) await message(context, '保存失败', '$e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: const CupertinoNavigationBar(middle: Text('我的配置二维码')),
    child: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: Container(
                color: CupertinoColors.white,
                padding: const EdgeInsets.all(Gap.md),
                child: QrImageView(data: widget.payload, size: 300),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(Gap.md),
            child: PrimaryButton(
              onPressed: saving ? null : _save,
              child: Text(saving ? '保存中…' : '保存到相册'),
            ),
          ),
        ],
      ),
    ),
  );
}
