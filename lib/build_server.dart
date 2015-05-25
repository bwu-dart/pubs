library pubs.build_server;

import 'dart:io' as io;
import 'package:path/path.dart' as path;
import 'package:archive/archive.dart';
import 'package:package_config/packagemap.dart';
import 'package:pubs/src/dependency_collector.dart';
import 'dart:collection';

/// The directory where the deployable artifacts are created.
final defaultOutputDirectory = new io.Directory('build/bin');
/// The directory where the entry point source files for the server application
/// are.
final defaultBinDirectory = new io.Directory('bin');
/// The name of the `pubspec.yaml` file is used to determine if the current
/// working directory is the root directory of a Dart package.
final defaultPubspecFile = new io.File('pubspec.yaml');
/// The directory where the packages links can be found.
final defaultPackagesRoot = new io.Directory('packages');
/// The `.packages` file containing the references to the source of the
/// dependencies.
final defaultPackagesFile = new io.File('.packages');
/// The directory where the output from `pub build web` was created.
final defaultStaticFilesSourceDirectory = new io.Directory('build/web');
/// The directory where the static web files are copied to.
final defaultStaticFilesDestinationDirectory =
    new io.Directory('build/bin/web');

/// Options to customize how the deployment directory is created.
class BuildOptions {
  /// The directory where the deployable directory is created.
  io.Directory outputDirectory = defaultOutputDirectory;

  /// The directory containing the server application entry points.
  io.Directory binDirectory = defaultBinDirectory;

  /// The packages directory used to resolve package dependencies.
  io.Directory packageRoot = defaultPackagesRoot;

  /// The `.package` file used to resolve package dependencies.
  /// If [packagesFile] is provided and found, [packageRoot] is ignored.
  io.File packagesFile = defaultPackagesFile;

  /// A directory containing static files to copy into the deployable directory.
  /// For example `build/web`.
  io.Directory get staticFilesSourceDirectory =>
      defaultStaticFilesSourceDirectory;

  /// The destination directory inside the deployable directory, where to copy
  /// the static files to.
  io.Directory get staticFilesDestinationDirectory =>
      defaultStaticFilesDestinationDirectory;

  /// Use the analyzer to find which Dart source files are actually used and
  /// skip copying all others. If files are imported they will be copied, no
  /// matter if the code is actually used. This is *no* tree-shaking mechanism.
  bool skipUnusedFiles = false;

  /// Explicitly include files and directories of packages which are
  /// skipped when [skipUnusedFiles] is [:true:] resource files.
  /// [include] is ignored when [skipUnusedFiles] is [:false:]
  /// The key of the map is the name of the package and the value is a list of
  /// paths relative to the packages `lib` directory.
  /// TODO(zoechi) add Glob support.
  Map<String, List<String>> include = {};

  /// Create a ZIP archive file containing all files copied to the
  /// [options.outputDirectory].
  bool createArchive = true;

  /// The filename to use for the generated ZIP archive.
  String archiveFileName = 'server_deployable.zip';
}

/// Creates a deployable directory and optional a ZIP archive from a Dart
/// server-side (console) application.
class BuildServer {
  BuildOptions options;

  io.File pubspecFile = defaultPubspecFile;

  /// A map from a dependency package name to the actual location on the file
  /// system.
  Map<String, io.Directory> packagesMapSource;

  /// A map from a dependency package name to the path inside the deployable
  /// directory where the files will be copied to.
  Map<String, io.Directory> packagesMapDestination;

  /// A list of files and directories to copy to the deployable directory.
  HashSet<CopyItem> itemsToCopy;

  /// If [options] is omitted the default configuration is used.
  BuildServer([this.options]) {
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
    switch (discoverPackageReferenceSystem()) {
      case PackageReferenceSystem.unknown:
        throw 'Can not determine how dependencies are referenced in this project. Please run "pub get" to fix it.';
      case PackageReferenceSystem.packagesLinks:
        packagesMapSource = packagesMapFromPackagesDirectory();
        break;
      case PackageReferenceSystem.packagesFile:
        packagesMapSource = packagesMapFromPackagesFile();
        break;
    }

    packagesMapDestination = {};
    packagesMapSource.forEach((packageName, packageDirectory) {
//      final packageDirectoryPath = path.join('packages', packageName);
      final destinationPath =
          path.join(options.outputDirectory.path, 'packages', packageName);
      packagesMapDestination[packageName] = new io.Directory(destinationPath);
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
    String content = packagesMapDestination.keys
        .map((k) => '${k}=${packagesMapDestination[k]}')
        .join('\n');
    content =
        '# Generated by pubs at ${new DateTime.now().toUtc().toIso8601String()}\n\n${content}\n';
    new io.File(path.join(options.outputDirectory.path, '.packages'))
        .writeAsStringSync(content);
  }

  /// Build the map from dependency packages to actual location on disk from the
  /// symlinks in the `packages` directory.
  Map<String, io.Directory> packagesMapFromPackagesDirectory() {
    final result = <String, io.Directory>{};
    final packageDirectories = options.packageRoot.listSync(recursive: false);
    packageDirectories.forEach((p) {
      final target = p.resolveSymbolicLinksSync();
      final targetType = io.FileSystemEntity.typeSync(target);
      switch (targetType) {
        case io.FileSystemEntityType.DIRECTORY:
          result[path.basename(p.path)] = new io.Directory(target);
          break;

        default:
          throw '"${target}" is not a directory.';
      }
    });
    return result;
  }

  /// Build the map from dependency packages to actual location on disk.
  /// This just loads and parses the `.packages` file.
  Map<String, io.Directory> packagesMapFromPackagesFile() {
    Packages packages = Packages.parse(options.packagesFile.readAsStringSync(),
        Uri.parse(io.Directory.current.path));

    return new Map<String, io.Directory>.fromIterable(
        packages.packageMapping.keys,
        key: (k) => k,
        value: (k) => new io.Directory.fromUri(packages.packageMapping[k]));
  }

  /// Returns whether a `packages` directory or a `.packages` file is used
  /// to reference the actualy location on the file system for dependencies.
  PackageReferenceSystem discoverPackageReferenceSystem() {
    if (options.packagesFile != null && options.packagesFile.existsSync()) {
      return PackageReferenceSystem.packagesFile;
    } else if (options.packageRoot != null &&
        options.packageRoot.existsSync()) {
      return PackageReferenceSystem.packagesLinks;
    } else {
      return PackageReferenceSystem.unknown;
    }
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
      final collector = new DependencyCollector()
        ..collect(options.binDirectory);
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

/// The list of supported methods to map dependency package names to actual
/// locations on the file system.
enum PackageReferenceSystem { unknown, packagesLinks, packagesFile, }

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
