library pubs.bin.pubs;

import 'package:pubs/pubs.dart';
import 'package:unscripted/unscripted.dart';

main([List<String> arguments]) => new Script(PubsScriptModel).execute(arguments);
//    arguments == null || arguments.length > 1
//        ? arguments
//        : new List<String>.from(arguments)..add('help'));
