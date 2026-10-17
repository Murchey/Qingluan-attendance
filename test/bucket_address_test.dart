import 'package:flutter_test/flutter_test.dart';
import 'package:qingluan_attendance/app/app.dart';
import 'package:qingluan_attendance/core/config/bucket_address.dart';
import 'package:qingluan_attendance/core/data/workspace.dart';

void main() {
  test('OSS and COS bucket links resolve endpoint and bucket', () {
    final oss = BucketAddress.parse(
      'OSS',
      ' https://team-log.oss-cn-hangzhou.aliyuncs.com/ ',
    );
    expect(oss.bucket, 'team-log');
    expect(oss.endpoint.toString(), 'https://oss-cn-hangzhou.aliyuncs.com');
    expect(oss.url.toString(), 'https://team-log.oss-cn-hangzhou.aliyuncs.com');
    final cos = BucketAddress.parse(
      'COS',
      'https://team-1250000000.cos.ap-guangzhou.myqcloud.com',
    );
    expect(cos.bucket, 'team-1250000000');
    expect(cos.endpoint.host, 'cos.ap-guangzhou.myqcloud.com');
  });
  test(
    'rejects object links, signed URLs, wrong providers and credentials',
    () {
      for (final value in [
        'http://team-log.oss-cn-hangzhou.aliyuncs.com',
        'https://team-log.oss-cn-hangzhou.aliyuncs.com/file.db',
        'https://team-log.oss-cn-hangzhou.aliyuncs.com?signature=secret',
        'https://user:secret@team-log.oss-cn-hangzhou.aliyuncs.com',
        'https://team-log.oss-cn-hangzhou.aliyuncs.com#fragment',
        'https://team-log.oss-cn-hangzhou.aliyuncs.com.evil.example',
        'https://team-1250000000.cos.ap-guangzhou.myqcloud.com',
      ]) {
        expect(() => BucketAddress.parse('OSS', value), throwsFormatException);
      }
    },
  );
  test(
    'legacy cloud configs resolve without changing independent S3 fields',
    () {
      final settings = <String, dynamic>{
        'endpoint': 'https://oss-cn-hangzhou.aliyuncs.com',
        'bucket': 'team-log',
      };
      expect(
        BucketAddress.configuredUrl(settings, 'OSS'),
        'https://team-log.oss-cn-hangzhou.aliyuncs.com',
      );
      expect(BucketAddress.configuredUrl(settings, 'COS'), '');
      settings['ossBucketUrl'] = '';
      expect(BucketAddress.configuredUrl(settings, 'OSS'), '');
      expect(settings['endpoint'], 'https://oss-cn-hangzhou.aliyuncs.com');
    },
  );
  testWidgets(
    'cloud providers show one link while S3 retains endpoint and bucket',
    (tester) async {
      final store = Workspace.memory();
      await tester.pumpWidget(QingLuanApp(store: store));
      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();
      expect(find.text('存储桶直链'), findsOneWidget);
      expect(find.text('Endpoint'), findsNothing);
      expect(find.text('Bucket'), findsNothing);
      await tester.tap(find.text('存储服务'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('S3 / MinIO'));
      await tester.pumpAndSettle();
      expect(find.text('存储桶直链'), findsNothing);
      expect(find.text('Endpoint'), findsOneWidget);
      expect(find.text('Bucket'), findsOneWidget);
      await tester.tap(find.text('存储服务'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('阿里云 OSS'));
      await tester.pumpAndSettle();
      expect(find.text('存储桶直链'), findsOneWidget);
      expect(find.text('Endpoint'), findsNothing);
    },
  );
}
