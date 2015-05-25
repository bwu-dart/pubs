library pubs.build_server_deployable;

import 'dart:io' as io;
import 'package:path/path.dart' as path;
import 'package:archive/archive.dart';
import 'package:package_config/discovery.dart';
import 'package:package_config/packages.dart';
import 'package:pubs/src/dependency_collector.dart';
import 'dart:collection';

/// The directory where the deployable artifacts are created.
const defaultOutputDirectory = 'build/bin';

/// The directory where the entry point source files for the server application
/// are.
const defaultBinDirectory = 'bin';

/// The name of the `pubspec.yaml` file is used to determine if the current
/// working directory is the root directory of a Dart package.
const defaultPubspecFile = 'pubspec.yaml';

/// The directory where the output from `pub build web` was created.
const defaultStaticFilesSourceDirectory = 'build/web';

/// The directory where the static web files are copied to.
const defaultStaticFilesDestinationDirectory = 'build/bin/web';

/// The name of the create ZIP archive file.
const defaultArchiveFileName = 'server_deployable.zip';

/// Options to customize how the deployment directory is created.
class BuildOptions {
  /// The directory where the deployable directory is created.
  io.Directory outputDirectory = new io.Directory(defaultOutputDirectory);

  /// The directory containing the server application entry points.
  io.Directory binDirectory = new io.Directory(defaultBinDirectory);

  /// The directory where the package discovery starts to find a `.packages`
  /// file or a `packages` directory. Default is the current working directory.
  io.Directory packageDiscoveryStart = io.Directory.current;

  /// A directory containing static files to copy into the deployable directory.
  /// For example `build/web`.
  io.Directory staticFilesSourceDirectory =
      new io.Directory(defaultStaticFilesSourceDirectory);

  /// The destination directory inside the deployable directory, where to copy
  /// the static files to.
  io.Directory staticFilesDestinationDirectory =
      new io.Directory(defaultStaticFilesDestinationDirectory);

  /// Use the analyzer to find which Dart source files are actually used and
  /// skip copying all others. If files are imported they will be copied, no
  /// matter if the code is actually used. This is *no* tree-shaking mechanism.
  bool skipUnusedFiles = false;

  /// Explicitly include files and directories of packages which are
  /// skipped when [skipUnusedFiles] is [:true:]. For example resource files.
  /// [include] is ignored when [skipUnusedFiles] is [:false:]
  /// The key of the map is the name of the package and the value is a list of
  /// paths relative to the packages `lib` directory.
  /// TODO(zoechi) add Glob support.
  Map<String, List<String>> include = {};

  /// Create a ZIP archive file containing all files copied to the
  /// [options.outputDirectory].
  bool createArchive = true;

  /// The filename to use for the generated ZIP archive.
  String archiveFileName = defaultArchiveFileName;
}

/// Creates a deployable directory and optional a ZIP archive from a Dart
/// server-side (console) application.
class BuildServerDeployable {
  BuildOptions options;

  io.File pubspecFile = new io.File(defaultPubspecFile);

  /// A map from a dependency package name to the actual location on the file
  /// system.
  Map<String, io.Directory> packagesMapSource;

  /// A map from a dependency package name to the path inside the deployable
  /// directory where the files will be copied to.
  Map<String, io.Directory> packagesMapDestination;

  /// A list of files and directories to copy to the deployable directory.
  HashSet<CopyItem> itemsToCopy;

  /// Set by [collectItemsToCopy] if [options.skipUnusedFiles] is [:true:].
  /// [collector] provides access to the result of the analyzer like
  /// 'referencedFiles' and 'referencedPackages'.
  DependencyCollector collector;

  /// If [options] is omitted the default configuration is used.
  BuildServerDeployable([this.options]) {
    if (options == null) {
      options = new BuildOptions();
    }
  }

  /// Executes the default steps to create a deployable directory
  void runAll() {
    purgeOutputDirectory();
    copyBinDirectory();
    buildPackagesMaps();
    collectItemsToCopy();
    copyItems();
    createPackagesFile();
    copyStaticFiles();
    createZipArchive();
  }

  /// Purge all files in the output directory before the new output is generated.
  void purgeOutputDirectory() {
    if (!_checkWorkingDirectory()) {
      throw 'No "pubspec.yaml" file found. "${io.Directory.current.path}" doesn\'t seem to be the root directory of a Dart package.';
    }
    if (options.outputDirectory.existsSync()) {
      options.outputDirectory.deleteSync(recursive: true);
    }
    options.outputDirectory.createSync(recursive: true);
  }

  /// check that the current working directory contains a `pubspec.yaml` to
  /// ensure we are in the right directory before deleting any files in `build`.
  bool _checkWorkingDirectory() {
    return pubspecFile.existsSync();
  }

  /// Copy the entire content of the `bin` directory to the deployable directory.
  void copyBinDirectory() {
    if (!options.binDirectory.existsSync()) {
      throw ('No "bin" directory found.');
    }
    copyDirectory(options.binDirectory, options.outputDirectory);
  }

  /// Build a map from dependency package names to the actual location on the
  /// file system. This method fills [packagesMapSource] and
  /// [packagesMapDestination].
  void buildPackagesMaps() {
    Map<String, Uri> packages =
        findPackagesFromFile(options.packageDiscoveryStart.uri).asMap();

    packagesMapSource = new Map<String, io.Directory>.fromIterable(
        packages.keys,
        key: (k) => k, value: (k) => new io.Directory.fromUri(packages[k]));

    packagesMapDestination = {};
    packagesMapSource.forEach((packageName, packageDirectory) {
      final destinationPath =
          path.join(options.outputDirectory.path, 'packages', packageName);
      packagesMapDestination[packageName] = new io.Directory(
          path.relative(destinationPath, from: options.outputDirectory.path));
    });
  }

  /// Copies the collected file and directory candidates to be copied to the
  /// deployable directory.
  void copyItems() {
    itemsToCopy.where((e) => e is CopyDirectory).forEach((e) {
      (e.destination as io.Directory).createSync(recursive: true);
    });
    itemsToCopy.where((e) => e is CopyFile).forEach((e) {
      new io.Directory(e.destination.parent.path).createSync(recursive: true);
      (e.source as io.File).copySync(e.destination.path);
    });
  }

  /// Create the `.packages` file in the deployable directory which maps from
  /// the dependency package names to the actual directory inside the deployable
  /// directory.
  void createPackagesFile() {
    String content = (options.skipUnusedFiles
            ? collector.referencedPackages
            : packagesMapDestination.keys)
        .map((k) => '${k}=${packagesMapDestination[k].path}')
        .join('\n');
    content =
        '# Generated by pubs at ${new DateTime.now().toUtc().toIso8601String()}\n\n${content}\n';
    new io.File(path.join(options.outputDirectory.path, '.packages'))
        .writeAsStringSync(content);
  }

  /// Copies files from the [options.staticFilesSourceDirectory] to
  void copyStaticFiles() {
    if (options.staticFilesSourceDirectory != null &&
        options.staticFilesSourceDirectory.existsSync()) {
      _copyImpl(options.staticFilesSourceDirectory,
          options.staticFilesDestinationDirectory,
          skipPackages: false, followLinks: true);
    }
  }

  /// Creates a ZIP archive file from all files copied to the deployable
  /// directory.
  void createZipArchive() {
    if (!options.createArchive) {
      return;
    }
    Archive archive = new Archive();
    options.outputDirectory
        .listSync(recursive: true, followLinks: true)
        .forEach((f) {
      ArchiveFile archiveFile;
      final name = path.relative(f.path, from: options.outputDirectory.path);
      if (f is io.Directory) {
        archiveFile = new ArchiveFile('${name}/', 0, []);
      } else if (f is io.File) {
        archiveFile = new ArchiveFile(
            name, f.statSync().size, (f as io.File).readAsBytesSync());
      } else {
        throw 'Invalid file type for file "${f.path}" (${io.FileSystemEntity.typeSync(f.path)}).';
      }
      archive.addFile(archiveFile);
    });
    final zipData = new ZipEncoder().encode(archive);
    new io.File(
        path.join(options.outputDirectory.parent.path, options.archiveFileName))
      ..createSync(recursive: true)
      ..writeAsBytesSync(zipData);
  }

  /// Copy the content of directory [source] into the directory [destination].
  /// No error is produced if the [source] directory doesn't exist.
  void copyDirectory(io.Directory source, io.Directory destination) {
    assert(source != null);
    assert(destination != null);

    if (source.existsSync()) {
      _copyImpl(source, destination);
    }
  }

  /// Collects all files that should be copied to the deployable directory and
  /// fills [itemsToCopy] with the found files.
  /// If [options.skipUnusedFiles] is [:true:] the analyzer is used to find out
  /// which files are actually referenced from the entry point and just add
  /// these to [itemsToCopy] while ignoring unreferended dependency packages and
  /// also unreferenced files from referenced dependencies.
  void collectItemsToCopy() {
    itemsToCopy = new HashSet<CopyItem>();
    if (options.skipUnusedFiles) {
      collector = new DependencyCollector()..collect(options.binDirectory);
      collector.referencedFiles.forEach((f) {
        itemsToCopy.add(new CopyFile._(new io.File(
            f.file.getAbsolutePath()), new io.File(
            path.join(options.outputDirectory.path, 'packages', f.uri.path))));
      });
      options.include.forEach((packageName, paths) {
        if (paths == null || paths.isEmpty) {
          paths = ['.'];
        }
        paths.forEach((p) {
          final entity =
              new io.File(path.join(packagesMapSource[packageName].path, p));
          final type = io.FileSystemEntity.typeSync(entity.path);
          switch (type) {
            case io.FileSystemEntityType.DIRECTORY:
              new io.Directory(entity.path)
                  .listSync(recursive: true)
                  .forEach((e) {
                final destinationPath = path.join(options.outputDirectory.path,
                    'packages', packageName, path.relative(e.path,
                        from: packagesMapSource[packageName].path));
                final itemType = io.FileSystemEntity.typeSync(e.path);
                switch (itemType) {
                  case io.FileSystemEntityType.DIRECTORY:
                    itemsToCopy.add(new CopyDirectory._(
                        new io.Directory(path.normalize(e.path)),
                        new io.Directory(destinationPath)));
                    break;
                  case io.FileSystemEntityType.FILE:
                    itemsToCopy
                        .add(new CopyFile._(e, new io.File(destinationPath)));
                    break;
                  default:
                  // do nothing
                }
              });
              break;
            case io.FileSystemEntityType.FILE:
              final destinationPath = path.join(options.outputDirectory.path,
                  'packages', packageName, path.relative(entity.path,
                      from: packagesMapSource[packageName].path));

              itemsToCopy
                  .add(new CopyFile._(entity, new io.File(destinationPath)));
              break;
            default:
            // ignore other types (broken links, not found, ...?
          }
        });
      });
    } else {
      packagesMapSource.forEach((packageName, sourceDirectory) {
        _copyImpl(packagesMapSource[packageName],
            packagesMapDestination[packageName]);
      });
    }
  }

  /// Copy [entity], a file or a directory recursively to the directory
  /// [destinationDir].
  /// [skipPackages] ignores directories named `packages` to not copy these
  /// auto-generated directories by pub in `bin` and subdirectories of `bin`
  /// while `packages` directories from `build/web` need to be copied.
  /// [followLinks]
  void _copyImpl(io.FileSystemEntity entity, io.Directory destinationDir,
      {bool skipPackages: true, bool followLinks: true}) {
    if (entity is io.Directory) {
      for (io.FileSystemEntity entity
          in entity.listSync(followLinks: followLinks)) {
        String name = path.basename(entity.path);

        if (skipPackages && name == 'packages') {
          continue;
        }
        if (entity is io.File) {
          _copyImpl(entity, destinationDir);
        } else if (entity is io.Directory) {
          _copyImpl(
              entity, new io.Directory(path.join(destinationDir.path, name)));
        } else if (entity is io.Link) {
          final target = entity.targetSync();
          if (target is io.File) {
            _copyImpl(target, destinationDir);
          } else if (target is io.Directory) {
            _copyImpl(
                target, new io.Directory(path.join(destinationDir.path, name)));
          }
        }
      }
    } else if (entity is io.File) {
      io.File destinationFile = new io.File(
          path.join(destinationDir.path, path.basename(entity.path)));

      if (!destinationFile.existsSync() ||
          entity.lastModifiedSync() != destinationFile.lastModifiedSync()) {
        destinationDir.createSync(recursive: true);
        entity.copySync(destinationFile.path);
      }
    } else {
      throw new StateError('unexpected type: ${entity.runtimeType}');
    }
  }
}

/// An item (file or directory) to copy to the deployable directory, mapping
/// from the source location to the destination locateion.
abstract class CopyItem {
  final io.FileSystemEntity source;
  io.FileSystemEntity destination;
  CopyItem._(this.source, this.destination) {
    assert(source != null);
  }

  @override
  int get hashCode => source.hashCode;

  operator ==(other) {
    return source.path == (other as CopyItem).source;
  }
}

/// A file to copy to the deployable directory.
class CopyFile extends CopyItem {
  CopyFile._(io.File file, io.File destination) : super._(file, destination);

  @override
  io.File get destination => super.destination;
}

/// A directory to copy to the deployable directory.
class CopyDirectory extends CopyItem {
  CopyDirectory._(io.Directory directory, io.Directory destination)
      : super._(directory, destination);

  @override
  io.Directory get destination => super.destination;
}
