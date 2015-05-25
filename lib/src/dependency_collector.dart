library pubs.src.dependency_collector;

import 'dart:collection';
import 'dart:io' as io;
import 'package:path/path.dart' as path;
import 'package:analyzer/file_system/file_system.dart' show Folder;
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:analyzer/source/package_map_provider.dart';
import 'package:analyzer/source/package_map_resolver.dart';
import 'package:analyzer/source/pub_package_map_provider.dart';
import 'package:analyzer/src/generated/element.dart';
import 'package:analyzer/src/generated/engine.dart';
import 'package:analyzer/src/generated/java_io.dart';
import 'package:analyzer/src/generated/sdk.dart';
import 'package:analyzer/src/generated/sdk_io.dart';
import 'package:analyzer/src/generated/source_io.dart';

import 'package:cli_util/cli_util.dart' as cli_util;

/// Uses the analyzer to find all packages which are imported by the entry
/// points and which files from these packages are imported.
class DependencyCollector {

  /// The sources which have been analyzed so far.  This is used to avoid
  /// analyzing a source more than once, and to compute the total number of
  /// sources analyzed for statistics.
  Set<Source> get sourcesAnalyzed =>
      _analysisDriver == null ? null : _analysisDriver.sourcesAnalyzed;

  /// All packages referenced using `package:` imports.
  Set<String> get referencedPackages =>
      _analysisDriver == null ? null : _analysisDriver.referencedPackages;

  /// All files referenced from packages using `package:` imports.
  Set<Source> get referencedFiles =>
      _analysisDriver == null ? null : _analysisDriver.referencedFiles;

  AnalysisDriver _analysisDriver;

  void collect(io.Directory directory, [DriverOptions options]) {
    if (options == null) {
      options = new DriverOptions();
    }
    final _files = collectFiles(directory);
    //final options = new DriverOptions()..packageRootPath = new io.Directory('sub_projects/sample_project/packages').absolute.path;
    _analysisDriver = new AnalysisDriver(options);
    _analysisDriver.analyze(_files.where((f) => isDartFile(f)));
  }

  /// Collect all Dart source files, recursively, under this [path] root, ignoring
  /// links.
  Iterable<io.File> collectFiles(io.Directory directory) {
    List<io.File> files = [];

    if (directory.existsSync()) {
      for (var entry
          in directory.listSync(recursive: true, followLinks: false)) {
        var relative = path.relative(entry.path, from: directory.path);

        if (isDartFile(entry) && !isInHiddenDir(relative)) {
          files.add(entry);
        }
      }
    }
    return files;
  }

  /// Returns `true` if this [entry] is a Dart file.
  bool isDartFile(io.FileSystemEntity entry) => isDartFileName(entry.path);

  /// Returns `true` if this relative path is a hidden directory.
  bool isInHiddenDir(String relative) =>
      path.split(relative).any((part) => part.startsWith("."));

  /// Returns `true` if this [fileName] is a Dart file.
  bool isDartFileName(String fileName) => fileName.endsWith('.dart');
}

class AnalysisDriver {

  /// The sources which have been analyzed so far.  This is used to avoid
  /// analyzing a source more than once, and to compute the total number of
  /// sources analyzed for statistics.
  Set<Source> sourcesAnalyzed = new HashSet<Source>();

  /// All packages referenced using `package:` imports.
  Set<String> referencedPackages = new HashSet<String>();

  /// All files referenced from packages using `package:` imports.
  Set<Source> referencedFiles = new HashSet<Source>();

  final DriverOptions options;

  AnalysisDriver(this.options);

  /// Return the number of sources that have been analyzed so far.
  int get numSourcesAnalyzed => sourcesAnalyzed.length;

  List<UriResolver> get resolvers {
    DartSdk sdk = new DirectoryBasedDartSdk(new JavaFile(sdkDir));
    List<UriResolver> resolvers = [new DartUriResolver(sdk)];
    if (options.packageRootPath != null) {
      JavaFile packageDirectory = new JavaFile(options.packageRootPath);
      resolvers.add(new PackageUriResolver([packageDirectory]));
    } else {
      PubPackageMapProvider pubPackageMapProvider = new PubPackageMapProvider(
          PhysicalResourceProvider.INSTANCE, sdk, options.runPubList);
      PackageMapInfo packageMapInfo = pubPackageMapProvider.computePackageMap(
          PhysicalResourceProvider.INSTANCE.getResource('.'));
      Map<String, List<Folder>> packageMap = packageMapInfo.packageMap;
      if (packageMap != null) {
        resolvers.add(new PackageMapUriResolver(
            PhysicalResourceProvider.INSTANCE, packageMap));
      }
    }
    // File URI resolver must come last so that files inside "/lib" are
    // are analyzed via "package:" URI's.
    resolvers.add(new FileUriResolver());
    return resolvers;
  }

  String get sdkDir {
    if (options.dartSdkPath != null) {
      return options.dartSdkPath;
    }
    // In case no SDK has been specified, fall back to inferring it
    // TODO: pass args to cli_util
    return cli_util.getSdkDir().path;
  }

  void analyze(Iterable<io.File> files) {
    AnalysisContext context = AnalysisEngine.instance.createAnalysisContext();
    context.analysisOptions = _buildAnalyzerOptions(options);
    context.sourceFactory = new SourceFactory(resolvers);
//    AnalysisEngine.instance.logger = new StdLogger();

    List<Source> sources = [];
    ChangeSet changeSet = new ChangeSet();
    for (io.File file in files) {
      JavaFile sourceFile = new JavaFile(path.normalize(file.absolute.path));
      Source source = new FileBasedSource.con2(sourceFile.toURI(), sourceFile);
      Uri uri = context.sourceFactory.restoreUri(source);
      if (uri != null) {
        // Ensure that we analyze the file using its canonical URI (e.g. if
        // it's in "/lib", analyze it using a "package:" URI).
        source = new FileBasedSource.con2(uri, sourceFile);
      }
      sources.add(source);
      changeSet.addedSource(source);
    }
    context.applyChanges(changeSet);

    // Temporary location
//    var project = new DartProject(context, sources);
    // This will get pushed into the generator (or somewhere comparable) when
    // we have a proper plugin.
//    ruleRegistry.forEach((lint) {
//      if (lint is ProjectVisitor) {
//        lint.visit(project);
//      }
//    });

//    List<AnalysisErrorInfo> errors = [];

    for (Source source in sources) {
      context.computeErrors(source);
//      errors.add(context.getErrors(source));
      sourcesAnalyzed.add(source);
    }

    if (options.visitTransitiveClosure) {
      // In the process of computing errors for all the sources in [sources],
      // the analyzer has visited the transitive closure of all libraries
      // referenced by those sources.  So now we simply need to visit all
      // library sources known to the analysis context, and all parts they
      // refer to.
      for (Source librarySource in context.librarySources) {
        for (Source source in _getAllUnitSources(context, librarySource)) {
          if (!sourcesAnalyzed.contains(source)) {
            //context.computeErrors(source);
//            errors.add(context.getErrors(source));
            sourcesAnalyzed.add(source);
            switch (source.uriKind) {
              case UriKind.DART_URI:
                // do nothing
                break;
              case UriKind.FILE_URI:
                referencedFiles.add(source);
                break;
              case UriKind.PACKAGE_URI:
                referencedFiles.add(source);
                referencedPackages.add(source.uri.pathSegments.first);
                break;
              default:
                print('Unknown Uri kind "${source.uriKind}".');
              // do nothing
            }
          }
        }
      }
    }
  }
  /// Yield the sources for all the compilation units constituting
  /// [librarySource] (including the defining compilation unit).
  Iterable<Source> _getAllUnitSources(
      AnalysisContext context, Source librarySource) {
    List<Source> result = <Source>[librarySource];
    result.addAll(context.getLibraryElement(librarySource).parts
        .map((CompilationUnitElement e) => e.source));
    return result;
  }

  AnalysisOptions _buildAnalyzerOptions(DriverOptions options) {
    AnalysisOptionsImpl analysisOptions = new AnalysisOptionsImpl();
    //analysisOptions.cacheSize = options.cacheSize;
    analysisOptions.analyzeFunctionBodies = false;
    analysisOptions.hint = false;
    analysisOptions.dart2jsHint = false;
    analysisOptions.generateImplicitErrors = false;
    analysisOptions.preserveComments = false;
    return analysisOptions;
  }
}

class DriverOptions {

  /// The maximum number of sources for which AST structures should be kept
  /// in the cache.  The default is 512.
  //int cacheSize = 512;

  /// The path to the dart SDK.
  String dartSdkPath;

  /// Whether to show lint warnings.
  bool enableLints = false;

  /// The path to the package root.
  String packageRootPath;

  /// Whether to show SDK warnings.
  bool showSdkWarnings = false;

  /// Whether to show lints for the transitive closure of imported and exported
  /// libraries.
  bool visitTransitiveClosure = true;

  /// If non-null, the function to use to run pub list.  This is used to mock
  /// out executions of pub list when testing the linter.
  RunPubList runPubList = null;
}
