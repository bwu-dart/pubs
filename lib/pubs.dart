library pubs.bin.pubs;

import 'dart:io' as io;
import 'package:unscripted/unscripted.dart';
import 'package:pubs/build_server_deployable.dart';
import 'dart:convert' show JSON;

class PubsScriptModel extends Object with BuildServerDeployableCommand {
  @Command(
      allowTrailingOptions: true,
      help: 'Extend "pub" with additional features.',
      plugins: const [const Completion()])
  PubsScriptModel();
}

class BuildServerDeployableCommand {
  @SubCommand(help: '''
Create a directory consiting of all files necessary to deploy the server
              application. Optionally create a ZIP archive.
''') // special string formatting for proper usage output
  deployable({ //
      @Option(help: '''
The absolute or relative path where the directory should be created.''',
          abbr: 'o',
          defaultsTo: defaultOutputDirectory) //
      String outputDirectory,
      //
      @Option(help: '''
The absolute or relative path to the directory containing the server
application entry points.''', //
          abbr: 'b', defaultsTo: defaultBinDirectory) //
      String binDirectory,
      //
      @Option(help: '''
The directory where the package discovery starts to find a `.packages` file or a
`packages` directory. Default is the current working directory.''',
          abbr: 'p') //
      String packageDiscoveryStart,
      //
      @Option(help: '''
A directory containing static files to copy into the deployable directory.''',
          abbr: 's',
          defaultsTo: defaultStaticFilesSourceDirectory) //
      String staticSource,
      //
      @Option(help: '''
The destination directory inside the deployable directory, where to copy the
static files to.''',
          abbr: 't',
          defaultsTo: defaultStaticFilesDestinationDirectory) //
      String staticDestination,
      //
      @Flag(help: '''
Use the analyzer to find which Dart source files are actually used and skip
copying all others. If files are imported they will be copied, no matter if the
code is actually used. This is *no* tree-shaking mechanism.''',
          abbr: 'k',
          defaultsTo: false,
          negatable: true) //
      bool skipUnused,
      //
      @Option(help: '''
Explicitly include files and directories of packages which are skipped when
"skipUnused" is "true". For example resource files which are not referenced by
any import statement.
"include" is ignored when "skipUnused" is "false".
The value needs to be a map as a valid JSON string.
The key of the map is the name of the package and the value is a list of
paths relative to the packages `lib` directory.
Example `{'mypackage': ['config/logconfig.json']}`''', //
          abbr: 'i') //
      String include,
      //
      @Flag(help: '''
Create a ZIP archive file containing all files copied to the outputDirectory.''',
          abbr: 'z',
          defaultsTo: false,
          negatable: true) //
      bool createZip,
      //
      @Option(help: '''
The name of the created ZIP archive file.''',
          abbr: 'n',
          defaultsTo: defaultArchiveFileName) //
      String zipName}) {
    //
    final options = new BuildOptions();
    if (outputDirectory != null) {
      options.outputDirectory = new io.Directory(outputDirectory);
    }
    if (binDirectory != null) {
      options.binDirectory = new io.Directory(binDirectory);
    }
    if (packageDiscoveryStart != null) {
      options.packageDiscoveryStart = new io.Directory(packageDiscoveryStart);
    }
    if (staticSource != null) {
      options.staticFilesSourceDirectory = new io.Directory(staticSource);
    }
    if (staticDestination != null) {
      options.staticFilesDestinationDirectory =
          new io.Directory(staticDestination);
    }
    if (skipUnused != null) {
      options.skipUnusedFiles = skipUnused;
    }
    if (include != null) {
      options.include = JSON.decode(include);
    }
    if (createZip != null) {
      options.createArchive = createZip;
    }
    if (zipName != null) {
      options.archiveFileName = zipName;
    }

    final build = new BuildServerDeployable(options);
    build.runAll();
  }
}
