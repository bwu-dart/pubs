library sample_project.example.example1;

import 'package:logging/logging.dart' show Logger, Level;
import 'package:quiver_log/log.dart' show BASIC_LOG_FORMATTER, PrintAppender;
import 'package:yaml/yaml.dart';

final _log = new Logger('sample2');

main() {
  Logger.root.level = Level.FINEST;
  var appender = new PrintAppender(BASIC_LOG_FORMATTER);
  appender.attachLogger(Logger.root);

  final pubspec = loadYaml('pubspec.yaml');
  _log.shout(pubspec['name']);
}
