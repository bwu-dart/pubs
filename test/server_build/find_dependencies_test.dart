@TestOn('vm')
library pubs.test.server_build.server_build.find_dependencies;

import 'dart:io' as io;
import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:pubs/build_server_deployable.dart';
import 'package:pubs/src/dependency_collector.dart';

final sampleProjectDirectory = new io.Directory('sub_projects/sample_project');
io.Directory get binDirectory => new io.Directory(
    path.join(sampleProjectDirectory.path, defaultBinDirectory));

main() {
  group('something', () {
    test('something', () {
      new DependencyCollector().collect(binDirectory);
    });
  });
}
