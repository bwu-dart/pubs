library bwu_log.tool.grind;

import 'package:grinder/grinder.dart';

const sourceDirs = const ['bin', 'lib', 'test', 'tool'];

main(List<String> args) => grind(args);

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
formatAll() => _format();

@Task('Run lint checks')
lint() => _lint();

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
