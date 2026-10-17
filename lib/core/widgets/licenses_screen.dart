import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

class LicensesScreen extends StatelessWidget {
  const LicensesScreen({super.key});
  Future<List<LicenseEntry>> load() => LicenseRegistry.licenses.toList();
  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: const CupertinoNavigationBar(middle: Text('开源许可')),
    child: SafeArea(
      child: FutureBuilder<List<LicenseEntry>>(
        future: load(),
        builder: (c, s) {
          if (!s.hasData) {
            return const Center(child: CupertinoActivityIndicator());
          }
          return ListView.builder(
            itemCount: s.data!.length,
            itemBuilder: (c, i) {
              final license = s.data![i];
              return Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      license.packages.join(', '),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    ...license.paragraphs.map(
                      (p) => Text(p.text, style: const TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    ),
  );
}
