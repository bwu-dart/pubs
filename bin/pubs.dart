library pubs.bin.pubs;

import 'dart:io' as io;
import 'package:pubs/build_server.dart';

main([List<String> args]) async {
  new BuildServer().runAll();
//  final io.Process pub = await io.Process.start('pub', args);
//  io.stdout.addStream(pub.stdout);
//  io.stderr.addStream(pub.stderr);
}
