library pubs.test.server_build.server_build;

import 'dart:io' as io;
import 'package:grinder/grinder.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';
import 'package:pubs/build_server_deployable.dart';

final sampleProjectDirectory = new io.Directory('sub_projects/sample_project');
io.Directory get outputDirectory => new io.Directory(
    path.join(sampleProjectDirectory.path, defaultOutputDirectory));

main() {
  group('something', () {
    setUp(() {
      new PubApp.global('grinder').run(['build-server'],
          runOptions: new RunOptions(
              workingDirectory: sampleProjectDirectory.path));
    });

    test('something', () {
      expect(new io.File(path.join(outputDirectory.path, 'sample1.dart'))
          .existsSync(), isTrue);
      expect(new io.File(path.join(outputDirectory.path, 'sample2.dart'))
          .existsSync(), isTrue);
      expect(new io.Directory(path.join(outputDirectory.path, 'packages'))
          .existsSync(), isTrue);
      expect(
          new io.Link(path.join(outputDirectory.path, 'packages')).existsSync(),
          isFalse);
    });
  });
}
