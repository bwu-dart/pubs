library sample_project.tool.grind;

import 'package:grinder/grinder.dart';
import 'dart:io' as io;
import 'package:which/which.dart';

const sourceDirs = const ['bin', 'example', 'lib', 'test', 'tool', 'web'];

main(List<String> args) => grind(args);

@Task('Create server deployable')
buildServer() => _buildServer();

@Task('Run analyzer')
analyze() => _analyze();

@Task('Runn all tests')
test() => _test();

@Task('Check everything')
@Depends(analyze, checkFormat, lint, test)
check() => _check();

@Task('Check source code format')
checkFormat() => _checkFormat();

@Task('Fix all source format issues')
format() => _format();

@Task('Run lint checks')
lint() => _lint();

_buildServer() {
  _activatePubs();
  Pub.global.run('pubs', arguments: ['deploy', 'server']);
}

void _activatePubs() {
  if (!Pub.global.isActivated('pubs')) {
    run(_sdkBin('pub'),
        arguments: ['global', 'activate', '-spath', '../../..']);
  }
}

// copied from Grinder because it's private there
// TODO(zoechi) remove if implementation becomes available
String _sdkBin(String name) {
  if (io.Platform.isWindows) {
    return name == 'dart' ? 'dart.exe' : '${name}.bat';
  } else if (io.Platform.isMacOS) {
    // If `dart` is not visible, we should join the sdk path and `bin/$name`.
    // This is only necessary in unusual circumstances, like when the script is
    // run from the Editor on macos.
    final _sdkOnPath = whichSync('dart', orElse: () => null) != null;
    return _sdkOnPath ? name : '${sdkDir.path}/bin/${name}';
  } else {
    return name;
  }
}

_analyze() => new PubApp.global('tuneup').run(['check']);

_check() => run('pub', arguments: ['publish', '-n']);

_checkFormat() {
  if (DartFmt.dryRun(sourceDirs)) context
      .fail('The package contains unformatted files.');
}

_format() => DartFmt.format(sourceDirs);

_lint() => new PubApp.global('linter')
    .run(['--stats', '-ctool/lintcfg.yaml']..addAll(sourceDirs));

_test() => new PubApp.local('test').run(['-pvm']);
