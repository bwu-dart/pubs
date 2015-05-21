library pubs.test.server_build.server_build;

import 'package:test/test.dart';
import 'package:grinder/grinder.dart';

main() {
  group('something', () {
    setUp(() {
      Pub.global.run('grinder',
          arguments: ['build-server'],
          runOptions: new RunOptions(
              workingDirectory: 'test/server_build/sample_project'));
    });

    test('something', () {});
  });
}
