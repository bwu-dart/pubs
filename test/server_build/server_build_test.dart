library pubs.test.server_build.server_build;

import 'dart:io' as io;
import 'package:test/test.dart';
import 'package:grinder/grinder.dart';
import 'package:pubs/build_server.dart';
import 'package:path/path.dart' as path;

final sampleProjectDirectory = new io.Directory('sub_projects/sample_project');
io.Directory get outputDirectory => new io.Directory(
    path.join(sampleProjectDirectory.path, defaultOutputDirectory.path));

main() {
  group('something', () {
    setUp(() {
      Pub.global.run('grinder',
          arguments: ['build-server'],
          runOptions: new RunOptions(
              workingDirectory: sampleProjectDirectory.path));
    });

    test('something', () {
      expect(new io.File(path.join(sampleProjectDirectory.path,
          outputDirectory.path, 'bin/sample1.dart')).existsSync(), isTrue);
      expect(new io.File(path.join(sampleProjectDirectory.path,
          outputDirectory.path, 'bin/sample2.dart')).existsSync(), isTrue);
      expect(new io.Directory(path.join(sampleProjectDirectory.path,
          outputDirectory.path, 'bin/packages')).existsSync(), isFalse);
      expect(new io.Link(path.join(sampleProjectDirectory.path,
          outputDirectory.path, 'bin/packages')).existsSync(), isFalse);
    });
  });
}
