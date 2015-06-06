# Pubs - tools for managing Pub packages.

[![Star this Repo](https://img.shields.io/github/stars/bwu-dart/pubs.svg?style=flat)](https://github.com/bwu-dart/pubs)
[![Pub Package](https://img.shields.io/pub/v/pubs.svg?style=flat)](https://pub.dartlang.org/packages/pubs)
[![Build Status](https://travis-ci.org/bwu-dart/pubs.svg?branch=travis)](https://travis-ci.org/bwu-dart/pubs)
[![Coverage Status](https://coveralls.io/repos/bwu-dart/pubs/badge.svg)](https://coveralls.io/r/bwu-dart/pubs)

## Usage

```
pub global activate pubs
pub global run pubs
```

### Commands

#### deployable

`deployable` is currently the only implemented command.

`pub global run pubs deployable` or just `pubs deployable` if you have 
`~/.pub-cache/bin` added to your path, copies files necessary to deploy your 
Dart server application into one directory (`build/bin` by default), similar 
to `pub build bin`. 

The steps it processes:
- purge the output directory
- copy content of `bin` to `build/bin/`
- copy the content of all dependencies to `build/bin/packages`
- create a `build/bin/.packages` file which links to the copied packages.
- copy `build/web` to `build/bin/web` (optional)
- create a ZIP file `build/server_deployable.zip` containing all files from
`build/bin`

Available options:

 
- `-o`, `--output-directory`           
The absolute or relative path where the directory should be created.  
(defaults to "build/bin")

- `-b`, `--bin-directory`              
The absolute or relative path to the directory containing the server
application entry points.  
(defaults to "bin")

- `-p`, `--package-discovery-start`
The directory where the package discovery starts to find a .packages file or a
packages directory. Default is the current working directory.
  
- `-s`, `--static-source`
A directory containing static files to copy into the deployable directory.  
(defaults to "build/web")
  
- `-t`, `--static-destination`
The destination directory inside the deployable directory, where to copy the
static files to.  
(defaults to "build/bin/web")

- `-k`, `--[no-]skip-unused`
Use the analyzer to find which Dart source files are actually used and skip
copying all others. If files are imported they will be copied, no matter if the
code is actually used. This is *no* tree-shaking mechanism.
  
- `-i`, `--include`
Explicitly include files and directories of packages which are skipped when
"skipUnused" is "true". For example resource files which are not referenced by
any import statement.  
"include" is ignored when "skipUnused" is "false".
The value needs to be a map as a valid JSON string.
The key of the map is the name of the package and the value is a list of
paths relative to the packages `lib` directory.
Example `{'mypackage': ['config/logconfig.json']}`

- `-z`, `--[no-]create-zip`
Create a ZIP archive file containing all files copied to the outputDirectory.

- `-n`, `--zip-name`
The name of the created ZIP archive file.  
(defaults to "server_deployable.zip")
  
- `-h`, `--help`
Print this usage information.


##### Call it from Dart code (like Grinder)

```
final options = new BuildOptions()
  ..createArchive = true;
  
new BuildServerDeployable(options).runAll();
```

For more control you can call call the individual tasks like

```
new BuildServerDeployable(options)
    ..purgeOutputDirectory()
    ..copyBinDirectory()
    ..buildPackagesMaps()
    ..collectItemsToCopy()
    ..copyItems()
    ..createPackagesFile()
    ..copyStaticFiles()
    ..createZipArchive()
```

Another option is to extend `BuildServerDeployable`

```
class MyServerDeployable extends {
  @override
  void runAll() {
    purgeOutputDirectory();
    copyBinDirectory();
    buildPackagesMaps();
    collectItemsToCopy();
    copyItems();
    createPackagesFile();
    copyStaticFiles();
    createZipArchive();  
    // add your custom methods before/after/in between as required      
  }
  
  // - add your own methods
  // - override methods
}
```
