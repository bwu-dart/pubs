library pubs.bin.pubs;

import 'dart:io' as io;
import 'package:pubs/build_server.dart';

main([List<String> args]) async {
  new BuildServer().runAll();
}
