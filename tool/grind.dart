library pubs.tool.grind;

export 'package:bwu_utils_dev/grinder/default_tasks.dart' hide main, testWeb;
import 'package:bwu_utils_dev/grinder/default_tasks.dart'
    show doInstallContentShell, grind, testTask, testTaskImpl;

main(List<String> args) {
  doInstallContentShell = false;
  testTask = ([_]) => testTaskImpl(['vm']);
  grind(args);
}
