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

class BuildOptions {
  /// The directory where the deployable directory is created.
  io.Directory outputDirectory = defaultOutputDirectory;
  /// The directory containing the server application entry points.
  io.Directory binDirectory = defaultBinDirectory;
  /// The packages directory used to resolve package dependencies.
  io.Directory packageRoot = defaultPackagesRoot;
  /// The `.package` file used to resolve package dependencies.
  /// If [packagesFile] is found, [packageRoot] is ignored.
  io.File packagesFile = defaultPackagesFile;
  /// A directory containing static files to copy into the deployable directory.
  io.Directory get staticFilesSourceDirectory =>
      defaultStaticFilesSourceDirectory;
  /// The destination directory where to copy the static files to.
  io.Directory get staticFilesDestinationDirectory =>
      defaultStaticFilesDestinationDirectory;
  /// Use the analyzer to find which Dart source files are actually used and
  /// skip copying all others.
  bool skipUnusedFiles = true;
  /// Explicitly include files and directories of packages which are
  /// skipped when [skipUnusedFiles] is [:true:] resource files.
  /// [include] is ignored when [skipUnusedFiles] is [:false:]
  /// The key of the map is the name of the package and the value is a list of
  /// paths relative to the packages `lib` directory.
  /// TODO(zoechi) add Glob support.
  Map<String, List<String>> include = {};
  /// Create a ZIP archive file containing all files in [defaultOutputDirectory].
  bool createArchive = true;
  /// The filename to use for the generated ZIP archive.
  String archiveFileName = 'server_deployable.zip';
}

class BuildServer {
  BuildOptions options;
  io.File pubspecFile = defaultPubspecFile;
  /// A map from a package name to the source directory.
  Map<String, io.Directory> packagesMapSource;
  Map<String, io.Directory> packagesMapDestination;
  HashSet<CopyItem> itemsToCopy;

  BuildServer([this.options]) {
    if (options == null) {
      options = new BuildOptions();
    }
  }

  void runAll() {
    purgeOutputDirectory();
    copyBinDirectory();
    buildPackagesMaps();
    collectItemsToCopy();
    copyItems();
    createPackagesFile();
    copyWeb();
    createZipArchive();
  }

  /// Clear the output directory before the new output is generated.
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
  /// ensure we are in the right directory before deleting any files.
  bool _checkWorkingDirectory() {
    return pubspecFile.existsSync();
  }

  void copyBinDirectory() {
    if (!options.binDirectory.existsSync()) {
      throw ('No "bin" directory found.');
    }
    copyDirectory(options.binDirectory, options.outputDirectory);
  }

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
      packagesMapDestination[packageName] = destinationPath;
    });
  }

  void copyItems() {
    itemsToCopy.where((e) => e is CopyDirectory).forEach((e) {
      (e.destination as io.Directory).createSync(recursive: true);
    });
    itemsToCopy.where((e) => e is CopyFile).forEach((e) {
      new io.Directory(e.destination.parent.path).createSync(recursive: true);
      (e.source as io.File).copySync(e.destination.path);
    });
  }

  void createPackagesFile() {
    String content = packagesMapDestination.keys
        .map((k) => '${k}=${packagesMapDestination[k]}')
        .join('\n');
    content =
        '# Generated by pubs at ${new DateTime.now().toUtc().toIso8601String()}\n\n${content}\n';
    new io.File(path.join(options.outputDirectory.path, '.packages'))
        .writeAsStringSync(content);
  }

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

  Map<String, io.Directory> packagesMapFromPackagesFile() {
    Packages packages = Packages.parse(options.packagesFile.readAsStringSync(),
        Uri.parse(io.Directory.current.path));

    return new Map<String, io.Directory>.fromIterable(
        packages.packageMapping.keys,
        key: (k) => k,
        value: (k) => new io.Directory.fromUri(packages.packageMapping[k]));
  }

  PackageReferenceSystem discoverPackageReferenceSystem() {
    if (defaultPackagesFile.existsSync()) {
      return PackageReferenceSystem.packagesFile;
    } else if (options.packageRoot.existsSync()) {
      return PackageReferenceSystem.packagesLinks;
    } else {
      return PackageReferenceSystem.unknown;
    }
  }

  void copyWeb() {
    if (options.staticFilesSourceDirectory == null) {
      return;
    }
    if (defaultStaticFilesSourceDirectory.existsSync()) {
      _copyImpl(options.staticFilesSourceDirectory,
          options.staticFilesDestinationDirectory,
          skipPackages: false, followLinks: true);
    }
  }

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

  void copyDirectory(io.Directory source, io.Directory destination) {
    assert(source != null);
    assert(destination != null);

    if (source.existsSync()) {
      _copyImpl(source, destination);
    }
  }

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

  /// [skipPackages] can be disabled when `packages` becomes a valid directory
  /// name to copy them as well.
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

enum PackageReferenceSystem { unknown, packagesLinks, packagesFile, }

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

class CopyFile extends CopyItem {
  CopyFile._(io.File file, io.File destination) : super._(file, destination);

  @override
  io.File get destination => super.destination;
}

class CopyDirectory extends CopyItem {
  CopyDirectory._(io.Directory directory, io.Directory destination)
      : super._(directory, destination);

  @override
  io.Directory get destination => super.destination;
}
