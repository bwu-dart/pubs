library pubs.bin.pubs;

import 'package:pubs/pubs.dart';
import 'package:unscripted/unscripted.dart';

main(arguments) => new Script(PubsScriptModel).execute(
    arguments.length > 1 ? arguments : arguments.toList()..add('help'));
