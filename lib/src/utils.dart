// Copyright 2015 Google. All rights reserved. Use of this source code is
// governed by a BSD-style license that can be found in the LICENSE file.

library grinder.utils;

import 'dart:async';
import 'dart:collection';
import 'dart:convert' show UTF8;
import 'dart:mirrors';
import 'dart:io';
import 'package:path/path.dart' as path;

Future<String> httpGet(String url) {
  HttpClient client = new HttpClient();
  return client.getUrl(Uri.parse(url)).then((HttpClientRequest request) {
    return request.close();
  }).then((HttpClientResponse response) {
    return response.toList();
  }).then((List<List> data) {
    return UTF8.decode(data.reduce((a, b) => a.addAll(b)));
  });
}

class ResettableTimer implements Timer {
  final Duration duration;
  final Function callback;

  Timer _timer;

  ResettableTimer(this.duration, this.callback) {
    _timer = new Timer(duration, callback);
  }

  void reset() {
    _timer.cancel();
    _timer = new Timer(duration, callback);
  }

  void cancel() => _timer.cancel();

  bool get isActive => _timer.isActive;
}

String camelToDashes(String input) {
  var segment = new RegExp(r'.[^A-Z]*');
  var matches = segment.allMatches(input);
  return matches
      .map((Match match) => withCapitalization(
          match.input.substring(match.start, match.end), false))
      .join('-');
}

// Upper-case or lower-case the first charater of a String.
String withCapitalization(String s, bool capitalized) {
  if (s.isEmpty || capitalized == null) return s;
  var firstLetter = s[0];
  firstLetter =
      capitalized ? firstLetter.toUpperCase() : firstLetter.toLowerCase();
  return firstLetter + s.substring(1);
}

// TODO: Remove this once this `dart:mirrors` bug is fixed:
//       http://dartbug.com/22601
declarationsEqual(DeclarationMirror decl1, decl2) =>
    decl2 is DeclarationMirror &&
        decl1.owner == decl2.owner &&
        decl1.simpleName == decl2.simpleName;

// TODO: Remove if this becomes supported by `dart:mirrors`:
//       http://dartbug.com/22591
Map<Symbol, DeclarationMirror> resolveExportedDeclarations(
    LibraryMirror library) {
  var resolved = {}..addAll(library.declarations);
  library.libraryDependencies.forEach((dependency) {
    if (dependency.isExport) {
      var shown = {};
      var hidden = [];
      dependency.combinators.forEach((combinator) {
        if (combinator.isShow) {
          combinator.identifiers.forEach((id) {
            shown[id] = dependency.targetLibrary.declarations[id];
          });
        }
        if (combinator.isHide) {
          hidden.addAll(combinator.identifiers);
        }
      });
      if (shown.isEmpty) {
        shown.addAll(dependency.targetLibrary.declarations);
        hidden.forEach(shown.remove);
      }
      resolved.addAll(shown);
    }
  });
  return new UnmodifiableMapView(resolved);
}

getFirstMatchingAnnotation(DeclarationMirror decl, bool test(annotation)) =>
    decl.metadata
        .map((mirror) => mirror.reflectee)
        .firstWhere(test, orElse: () => null);

/// A simple way to expose a default value that can be overridden within zones.
class ZonedValue<T> {
  final T _rootValue;
  final _valueKey = new Object();
  final _finalKey = new Object();

  ZonedValue(T rootValue) : _rootValue = rootValue;

  withValue(T value, f(), {bool isFinal: false}) {
    if (this.isFinal) {
      throw new StateError('Cannot override final zoned value');
    }
    return runZoned(f, zoneValues: {_valueKey: value, _finalKey: isFinal});
  }

  bool get isFinal {
    var parentIsFinal = Zone.current[_finalKey];
    return parentIsFinal != null && parentIsFinal;
  }

  T get value {
    // TODO: Allow null values when http://dartbug.com/21247 is fixed.
    var v = Zone.current[_valueKey];
    return v != null ? v : _rootValue;
  }
}

/// Given a [String], [File], or list of strings or files, coerce the
/// [filesOrPaths] param into a list of strings.
List<String> coerceToPathList(filesOrPaths) {
  if (filesOrPaths is! Iterable) filesOrPaths = [filesOrPaths];
  return filesOrPaths.map((item) {
    if (item is String) return item;
    if (item is FileSystemEntity) return item.path;
    return '${item}';
  }).toList();
}

/// Takes a list of paths and if an element is a directory it expands it to
/// the Dart source files contained by this directory, otherwise the element is
/// added to the result unchanged.
Set<String> findDartSourceFiles(Iterable<String> paths) {
  /// Returns `true` if this [fileName] is a Dart file.
  bool _isDartFileName(String fileName) => fileName.endsWith('.dart');

  /// Returns `true` if this relative path is a hidden directory.
  bool _isInHiddenDir(String relative) =>
      path.split(relative).any((part) => part.startsWith("."));

  Set<String> _findDartSourceFiles(Directory directory) {
    var files = new Set<String>();
    if (directory.existsSync()) {
      for (var entry
          in directory.listSync(recursive: true, followLinks: false)) {
        var relative = path.relative(entry.path, from: directory.path);
        if (_isDartFileName(entry.path) && !_isInHiddenDir(relative)) {
          files.add(entry.path);
        }
      }
    }
    return files;
  }

  var files = new Set<String>();

  paths.forEach((p) {
    if (FileSystemEntity.typeSync(p) == FileSystemEntityType.DIRECTORY) {
      files.addAll(_findDartSourceFiles(new Directory(p)));
    } else {
      files.add(p);
    }
  });
  return files;
}
