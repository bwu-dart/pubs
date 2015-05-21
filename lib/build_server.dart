library pubs.build_server;

import 'dart:io' as io;
import 'package:path/path.dart' as path;
import 'package:archive/archive.dart';
import 'package:packages_file/packages_file.dart';
import 'package:packages_file/loader.dart';

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

class BuildServer {
  io.Directory get outputDirectory => defaultOutputDirectory;
  io.Directory get binDirectory => defaultBinDirectory;
  io.File get pubspecFile => defaultPubspecFile;
  io.Directory get packagesRoot => defaultPackagesRoot;
  io.File get packagesFile => defaultPackagesFile;
  io.Directory get staticFilesSourceDirectory =>
      defaultStaticFilesSourceDirectory;
  io.Directory get staticFilesDestinationDirectory =>
      defaultStaticFilesDestinationDirectory;

  void runAll() {
    purgeOutputDirectory();
    copyBinDirectory();
    copyPackages();
    copyWeb();
    createZipArchive();
  }

  /// Clear the output directory before the new output is generated.
  void purgeOutputDirectory() {
    if (!_checkWorkingDirectory()) {
      throw 'No "pubspec.yaml" file found. "${io.Directory.current.path}" doesn\'t seem to be the root directory of a Dart package.';
    }
    if (outputDirectory.existsSync()) {
      outputDirectory.deleteSync(recursive: true);
    }
    outputDirectory.createSync(recursive: true);
  }

  /// check that the current working directory contains a `pubspec.yaml` to
  /// ensure we are in the right directory before deleting any files.
  bool _checkWorkingDirectory() {
    return pubspecFile.existsSync();
  }

  void copyBinDirectory() {
    if (!binDirectory.existsSync()) {
      throw ('No "bin" directory found.');
    }
    copyDirectory(binDirectory, outputDirectory);
  }

  void copyPackages() {
    switch (discoverPackageReferenceSystem()) {
      case PackageReferenceSystem.unknown:
        throw 'It is unknown how packages are referenced in this project. Please run "pub get" to fix it.';
      case PackageReferenceSystem.packagesLinks:
        return copyPackagesUsingPackagesDirectory();
      case PackageReferenceSystem.packagesFile:
        return copyPackagesUsingPackagesFile();
    }
  }

  void copyPackagesUsingPackagesDirectory() {
    final packages = packagesDirectoriesFromPackagesDirectory();
    packages.forEach((k, v) {
      _copyImpl(
          v, new io.Directory(path.join(outputDirectory.path, 'packages', k)));
    });
  }

  void copyPackagesUsingPackagesFile() {
    // TODO(zoechi)
  }

  Map<String, io.Directory> packagesDirectoriesFromPackagesDirectory() {
    final result = <String, io.Directory>{};
    final packageDirectories = packagesRoot.listSync(recursive: false);
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

  Map<String, io.Directory> packagesDirectoriesFromPackagesFile() {
    Packages packages = loadPackageConfigSync(packagesFile);

    print(packages);
    return {};
  }

  PackageReferenceSystem discoverPackageReferenceSystem() {
    if (defaultPackagesFile.existsSync()) {
      return PackageReferenceSystem.packagesFile;
    } else if (packagesRoot.existsSync()) {
      return PackageReferenceSystem.packagesLinks;
    } else {
      return PackageReferenceSystem.unknown;
    }
  }

  void copyWeb() {
    if (defaultStaticFilesSourceDirectory.existsSync()) {
      _copyImpl(staticFilesSourceDirectory, staticFilesDestinationDirectory,
          skipPackages: false, followLinks: true);
    }
  }

  void createZipArchive() {
    Archive archive = new Archive();
    outputDirectory.listSync(recursive: true, followLinks: true).forEach((f) {
      ArchiveFile archiveFile;
      final name = path.relative(f.path, from: outputDirectory.path);
      print(name);
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
    new io.File(path.join(outputDirectory.parent.path, 'server_deployable.zip'))
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

  /// [skipPackages] can be disabled when `packages` becomes a valid directory
  /// name to copy them as well.
  void _copyImpl(io.FileSystemEntity entity, io.Directory destinationDir,
      {bool skipPackages: true, bool followLinks: false}) {
    if (entity is io.Directory) {
      for (io.FileSystemEntity entity
          in entity.listSync(followLinks: followLinks)) {
        String name = path.basename(entity.path);

        if (entity is io.File) {
          _copyImpl(entity, destinationDir);
        } else if (entity is io.Directory) {
          _copyImpl(
              entity, new io.Directory(path.join(destinationDir.path, name)));
        } else if (entity is io.Link) {
          if (path.basename(entity.path) != 'packages' || !skipPackages) {
            final target = entity.targetSync();
            if (target is io.File) {
              _copyImpl(target, destinationDir);
            } else if (target is io.Directory) {
              _copyImpl(target,
                  new io.Directory(path.join(destinationDir.path, name)));
            }
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
