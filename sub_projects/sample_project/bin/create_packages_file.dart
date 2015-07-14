import 'dart:io' as io;
import 'package:path/path.dart' as path;

main() {
  final directories = new io.Directory('packages').listSync();
  final result = {};
  directories.forEach((p) {
    final target = p.resolveSymbolicLinksSync();
    final targetType = io.FileSystemEntity.typeSync(target);
    switch (targetType) {
      case io.FileSystemEntityType.DIRECTORY:
        result[path.basename(p.path)] = new io.Directory(target).path;
        break;

      default:
        throw '"${target}" is not a directory.';
    }
  });
  createPackagesFile(result);
}

void createPackagesFile(Map<String, io.Directory> packages) {
  String content = packages.keys.map((k) => '${k}:file:${packages[k]}').join('\n');
  content =
      '# Generated by pubs at ${new DateTime.now().toUtc().toIso8601String()}\n\n${content}\n';
  new io.File('.packages').writeAsStringSync(content);
}
