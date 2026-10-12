// Dependency inventory + vulnerability assessment for a specific commit.
//
// Builds one inventory of everything resolved for the checked-out commit:
//   * Pub packages, from the root `pubspec.lock` (workspace lockfile), and
//   * Maven/Gradle artifacts, from the dependency-graph snapshot generated for
//     `apps/playground/android` (GitHub Dependency Graph Gradle Plugin),
// cross-checks it against the repo (so an empty, partial, or stale snapshot is
// caught), looks every component up in OSV (https://osv.dev), and writes
// evidence files tied to the commit SHA.
//
// This is deliberately separate from GitHub's default-branch Dependabot alert
// counts: it answers "is *this* SHA's resolved inventory complete, and does it
// contain High/Critical advisories?".
//
// It never dismisses, ignores, or accepts anything on its own. Documented human
// exceptions live in `.github/dependency-exceptions.json` and are always
// reported. See docs/DEPENDENCY_SECURITY.md.
//
// Usage:
//   dart run tool/dependency_inventory.dart validate-snapshot --sha <sha> --gradle-snapshot <file|dir>
//   dart run tool/dependency_inventory.dart assess            --sha <sha> --gradle-snapshot <file|dir>
//
// Exit codes: 0 = complete inventory, no blocking findings
//             1 = complete inventory, blocking (High/Critical/unrated) findings
//             2 = INCOMPLETE — inventory/lookup failed; NOT a clean result
//             64 = usage error
import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Minimum number of Maven components a real Android build resolves. The
/// playground resolves several hundred (Android Gradle Plugin alone is dozens),
/// so anything near zero means the collection did not actually run.
const int minGradleComponents = 100;

/// Coordinates (`group:artifact`) that must appear in any real snapshot of the
/// playground: build plugins, the Flutter engine embedding, and the AndroidX
/// WebView library the SDK's `webview_flutter_android` dependency brings in.
const List<String> requiredGradleCoordinates = [
  'com.android.tools.build:gradle',
  'org.jetbrains.kotlin:kotlin-gradle-plugin',
  'io.flutter:flutter_embedding_release',
  'androidx.webkit:webkit',
];

const int maxExceptionDays = 180;
const String osvApi = 'https://api.osv.dev/v1';

enum Verdict { pass, findings, incomplete }

class Component {
  const Component(
    this.ecosystem,
    this.name,
    this.version,
    this.source, {
    this.scope = 'unclassified',
  });

  /// OSV ecosystem: `Maven` or `Pub`.
  final String ecosystem;

  /// `group:artifact` for Maven, the package name for Pub.
  final String name;
  final String version;

  /// `gradle` or `pub`.
  final String source;

  /// For Maven components: `app-runtime` (on the playground's release/debug
  /// runtime classpath) or `build-tooling` (everything else Gradle resolves —
  /// plugin classpaths, AGP internals), when a runtime classpath is supplied;
  /// otherwise `unclassified`. Pub components are always `pub`.
  final String scope;

  Component withScope(String scope) =>
      Component(ecosystem, name, version, source, scope: scope);

  String get key => '$ecosystem|$name|$version';

  Map<String, Object?> toJson() => {
    'ecosystem': ecosystem,
    'name': name,
    'version': version,
    'source': source,
    'scope': scope,
  };
}

class SnapshotInfo {
  SnapshotInfo(this.file, this.sha256Hex, this.json);
  final String file;
  final String sha256Hex;
  final Map<String, Object?> json;
}

/// Parses `pkg:maven/<group>/<artifact>@<version>?<qualifiers>`.
Component? componentFromPurl(String purl) {
  const prefix = 'pkg:maven/';
  if (!purl.startsWith(prefix)) return null;
  var rest = purl.substring(prefix.length);
  final q = rest.indexOf('?');
  if (q >= 0) rest = rest.substring(0, q);
  final at = rest.lastIndexOf('@');
  final slash = rest.indexOf('/');
  if (at < 0 || slash < 0 || slash > at) return null;
  final group = Uri.decodeComponent(rest.substring(0, slash));
  final artifact = Uri.decodeComponent(rest.substring(slash + 1, at));
  final version = Uri.decodeComponent(rest.substring(at + 1));
  if (group.isEmpty || artifact.isEmpty || version.isEmpty) return null;
  return Component('Maven', '$group:$artifact', version, 'gradle');
}

/// Extracts hosted Pub packages from a `pubspec.lock`. SDK and path packages
/// are not downloaded from a registry and are skipped; git packages are
/// returned in [unsupported] so the caller can flag them.
({List<Component> components, List<String> unsupported}) parsePubLockfile(
  String content,
) {
  final components = <Component>[];
  final unsupported = <String>[];
  String? name;
  String? source;
  String? version;

  void flush() {
    if (name == null) return;
    if (source == 'hosted' && version != null) {
      components.add(Component('Pub', name!, version!, 'pub', scope: 'pub'));
    } else if (source == 'git') {
      unsupported.add(name!);
    }
    name = null;
    source = null;
    version = null;
  }

  var inPackages = false;
  for (final line in const LineSplitter().convert(content)) {
    if (line.startsWith('packages:')) {
      inPackages = true;
      continue;
    }
    if (inPackages && line.isNotEmpty && !line.startsWith(' ')) {
      flush();
      inPackages = false;
    }
    if (!inPackages) continue;
    final entry = RegExp(r'^  ([A-Za-z0-9_]+):\s*$').firstMatch(line);
    if (entry != null) {
      flush();
      name = entry.group(1);
      continue;
    }
    final field = RegExp(
      r'^    (source|version):\s*"?([^"\s]+)"?\s*$',
    ).firstMatch(line);
    if (field != null) {
      if (field.group(1) == 'source') {
        source = field.group(2);
      } else {
        version = field.group(2);
      }
    }
  }
  flush();
  return (components: components, unsupported: unsupported);
}

/// Components resolved in a dependency-submission snapshot.
List<Component> gradleComponents(Map<String, Object?> snapshot) {
  final out = <String, Component>{};
  final manifests = snapshot['manifests'];
  if (manifests is! Map) return const [];
  for (final manifest in manifests.values) {
    if (manifest is! Map) continue;
    final resolved = manifest['resolved'];
    if (resolved is! Map) continue;
    for (final dep in resolved.values) {
      if (dep is! Map) continue;
      final purl = dep['package_url'];
      if (purl is! String) continue;
      final c = componentFromPurl(purl);
      if (c != null) out[c.key] = c;
    }
  }
  return out.values.toList();
}

/// Resolved coordinates (`group:artifact@version`) from the text output of
/// `./gradlew :app:dependencies --configuration <name>`. Constraints `(c)`,
/// unresolvable `(n)` nodes and sub-projects are skipped; `a:b:1 -> 2` yields
/// the resolved version 2. Unresolved (`FAILED`) nodes are returned in
/// [failed].
({Set<String> resolved, List<String> failed}) parseRuntimeClasspath(
  String content,
) {
  final resolved = <String>{};
  final failed = <String>[];
  final node = RegExp(r'^[|\s]*[+\\]---\s+(.+)$');
  final coordinate = RegExp(
    r'^([\w.\-]+):([\w.\-]+)(?::(\{[^}]*\}|\S+))?(?:\s+->\s+(\S+))?',
  );
  for (final line in const LineSplitter().convert(content)) {
    final m = node.firstMatch(line);
    if (m == null) continue;
    final text = m.group(1)!;
    if (text.startsWith('project ') ||
        text.contains('(c)') ||
        text.contains('(n)')) {
      continue;
    }
    final c = coordinate.firstMatch(text);
    if (c == null) continue;
    final name = '${c.group(1)}:${c.group(2)}';
    if (text.contains('FAILED')) {
      failed.add(name);
      continue;
    }
    final version = c.group(4) ?? c.group(3);
    if (version == null || version.startsWith('{')) continue;
    resolved.add('$name@$version');
  }
  return (resolved: resolved, failed: failed);
}

/// Every dependency Gradle itself reports on the app runtime classpath must be
/// present in the snapshot at the same version. This is the independent
/// cross-check that the dependency graph matches the real resolution.
List<String> checkRuntimeClasspathCoverage({
  required Set<String> runtime,
  required Set<String> snapshotKeys,
}) {
  final missing = runtime.where((r) => !snapshotKeys.contains(r)).toList()
    ..sort();
  return [
    for (final m in missing)
      'Resolved by Gradle on the app runtime classpath but absent from the '
          'snapshot: $m',
  ];
}

/// Structural checks that make an empty/partial/stale snapshot impossible to
/// mistake for a clean result. Returns human-readable problems (empty = OK).
List<String> validateSnapshot(
  Map<String, Object?> snapshot, {
  required String expectedSha,
  String label = 'snapshot',
}) {
  final problems = <String>[];
  final sha = snapshot['sha'];
  if (sha is! String || sha.toLowerCase() != expectedSha.toLowerCase()) {
    problems.add(
      '$label is for commit ${sha ?? '<missing>'}, expected $expectedSha '
      '(stale or wrong snapshot).',
    );
  }
  if (snapshot['scanned'] is! String) {
    problems.add('$label has no "scanned" timestamp.');
  }
  final manifests = snapshot['manifests'];
  if (manifests is! Map || manifests.isEmpty) {
    problems.add('$label contains no manifests.');
    return problems;
  }
  final components = gradleComponents(snapshot);
  if (components.length < minGradleComponents) {
    problems.add(
      '$label resolves only ${components.length} Maven components '
      '(expected at least $minGradleComponents); dependency collection '
      'looks empty or partial.',
    );
  }
  final names = components.map((c) => c.name).toSet();
  for (final required in requiredGradleCoordinates) {
    if (!names.contains(required)) {
      problems.add('$label is missing required coordinate $required.');
    }
  }
  return problems;
}

/// Native dependencies declared literally in the Android build files of the
/// Flutter plugins the playground uses (`implementation("g:a:v")` and buildscript
/// `classpath("g:a:v")`). Each must show up in the Gradle snapshot, which
/// proves plugin sub-projects — not just the app module — were resolved.
List<String> checkPluginCoverage({
  required String pluginsFileContent,
  required Set<String> snapshotCoordinates,
  required String Function(String path) readGradleFile,
}) {
  final problems = <String>[];
  final Object? decoded;
  try {
    decoded = jsonDecode(pluginsFileContent);
  } on FormatException catch (e) {
    return ['Cannot parse .flutter-plugins-dependencies: ${e.message}'];
  }
  final android = decoded is Map && decoded['plugins'] is Map
      ? (decoded['plugins'] as Map)['android']
      : null;
  if (android is! List || android.isEmpty) {
    return ['.flutter-plugins-dependencies lists no Android plugins.'];
  }
  final declared = RegExp(
    r'''(?<![A-Za-z])(?:implementation|api|runtimeOnly|compileOnly|classpath)\s*\(?\s*["']([\w.\-]+:[\w.\-]+):([^"'$:]+)["']''',
  );
  for (final plugin in android) {
    if (plugin is! Map) continue;
    final name = plugin['name'];
    final path = plugin['path'];
    if (name is! String || path is! String) continue;
    final text = <String>[];
    for (final f in const ['build.gradle', 'build.gradle.kts']) {
      final content = readGradleFile('${path}android/$f');
      if (content.isNotEmpty) text.add(content);
    }
    if (text.isEmpty) {
      problems.add('Android plugin $name: no android/build.gradle found.');
      continue;
    }
    for (final match in declared.allMatches(text.join('\n'))) {
      final coordinate = match.group(1)!;
      if (!snapshotCoordinates.contains(coordinate)) {
        problems.add(
          'Android plugin $name declares $coordinate but it is absent from '
          'the Gradle snapshot.',
        );
      }
    }
  }
  return problems;
}

// --- Severity ---------------------------------------------------------------

String ratingFromScore(double score) {
  if (score >= 9.0) return 'CRITICAL';
  if (score >= 7.0) return 'HIGH';
  if (score >= 4.0) return 'MEDIUM';
  if (score > 0.0) return 'LOW';
  return 'NONE';
}

/// CVSS v3.x base score from a vector string, or null if unparsable.
double? cvssV3Score(String vector) {
  if (!vector.startsWith('CVSS:3')) return null;
  final m = <String, String>{};
  for (final part in vector.split('/').skip(1)) {
    final kv = part.split(':');
    if (kv.length == 2) m[kv[0]] = kv[1];
  }
  const av = {'N': 0.85, 'A': 0.62, 'L': 0.55, 'P': 0.2};
  const ac = {'L': 0.77, 'H': 0.44};
  const ui = {'N': 0.85, 'R': 0.62};
  const cia = {'H': 0.56, 'L': 0.22, 'N': 0.0};
  final changed = m['S'] == 'C';
  final pr = changed
      ? const {'N': 0.85, 'L': 0.68, 'H': 0.5}
      : const {'N': 0.85, 'L': 0.62, 'H': 0.27};
  final a = av[m['AV']];
  final c = ac[m['AC']];
  final p = pr[m['PR']];
  final u = ui[m['UI']];
  final ci = cia[m['C']];
  final ii = cia[m['I']];
  final ai = cia[m['A']];
  if ([a, c, p, u, ci, ii, ai].contains(null) || m['S'] == null) return null;
  final iss = 1 - (1 - ci!) * (1 - ii!) * (1 - ai!);
  final impact = changed
      ? 7.52 * (iss - 0.029) - 3.25 * _pow(iss - 0.02, 15)
      : 6.42 * iss;
  if (impact <= 0) return 0;
  final exploitability = 8.22 * a! * c! * p! * u!;
  final raw = changed
      ? 1.08 * (impact + exploitability)
      : impact + exploitability;
  return _roundUp(raw > 10 ? 10 : raw);
}

double _pow(double base, int exp) {
  var r = 1.0;
  for (var i = 0; i < exp; i++) {
    r *= base;
  }
  return r;
}

double _roundUp(double v) {
  final i = (v * 100000).round();
  if (i % 10000 == 0) return i / 100000.0;
  return ((i ~/ 10000) + 1) / 10.0;
}

/// `CRITICAL|HIGH|MEDIUM|LOW|UNRATED` for an OSV vulnerability record.
String severityOf(Map<String, Object?> vuln) {
  final db = vuln['database_specific'];
  if (db is Map && db['severity'] is String) {
    final s = (db['severity'] as String).toUpperCase();
    if (s == 'MODERATE') return 'MEDIUM';
    if (const ['CRITICAL', 'HIGH', 'MEDIUM', 'LOW'].contains(s)) return s;
  }
  final severities = vuln['severity'];
  if (severities is List) {
    for (final s in severities) {
      if (s is Map && s['score'] is String) {
        final score = cvssV3Score(s['score'] as String);
        if (score != null) return ratingFromScore(score);
      }
    }
  }
  return 'UNRATED';
}

bool isBlocking(String severity) =>
    severity == 'CRITICAL' || severity == 'HIGH' || severity == 'UNRATED';

// --- Exceptions -------------------------------------------------------------

class ExceptionEntry {
  ExceptionEntry(
    this.advisory,
    this.package,
    this.reason,
    this.approvedBy,
    this.expires,
  );
  final String advisory;
  final String package;
  final String reason;
  final String approvedBy;
  final DateTime expires;

  Map<String, Object?> toJson() => {
    'advisory': advisory,
    'package': package,
    'reason': reason,
    'approvedBy': approvedBy,
    'expires': expires.toIso8601String().substring(0, 10),
  };
}

/// Parses the human exception register. Problems are returned, not thrown, so
/// an invalid register makes the assessment INCOMPLETE rather than silently
/// ignoring entries.
({
  List<ExceptionEntry> active,
  List<ExceptionEntry> expired,
  List<String> problems,
})
parseExceptions(String? content, DateTime now) {
  final active = <ExceptionEntry>[];
  final expired = <ExceptionEntry>[];
  final problems = <String>[];
  if (content == null || content.trim().isEmpty) {
    return (active: active, expired: expired, problems: problems);
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(content);
  } on FormatException catch (e) {
    problems.add('Exception register is not valid JSON: ${e.message}');
    return (active: active, expired: expired, problems: problems);
  }
  final list = decoded is Map ? decoded['exceptions'] : null;
  if (list is! List) {
    problems.add('Exception register must be {"exceptions": [...]}.');
    return (active: active, expired: expired, problems: problems);
  }
  final today = DateTime.utc(now.year, now.month, now.day);
  final horizon = today.add(const Duration(days: maxExceptionDays));
  for (var i = 0; i < list.length; i++) {
    final e = list[i];
    String field(String k) => e is Map && e[k] is String ? e[k] as String : '';
    final missing = [
      for (final k in const [
        'advisory',
        'package',
        'reason',
        'approvedBy',
        'expires',
      ])
        if (field(k).trim().isEmpty) k,
    ];
    if (missing.isNotEmpty) {
      problems.add('Exception #$i is missing: ${missing.join(', ')}.');
      continue;
    }
    final expires = DateTime.tryParse(field('expires'));
    if (expires == null) {
      problems.add('Exception #$i has an invalid "expires" date.');
      continue;
    }
    final entry = ExceptionEntry(
      field('advisory'),
      field('package'),
      field('reason'),
      field('approvedBy'),
      DateTime.utc(expires.year, expires.month, expires.day),
    );
    if (entry.expires.isBefore(today)) {
      expired.add(entry);
    } else if (entry.expires.isAfter(horizon)) {
      problems.add(
        'Exception #$i (${entry.advisory}) expires more than '
        '$maxExceptionDays days out.',
      );
    } else {
      active.add(entry);
    }
  }
  return (active: active, expired: expired, problems: problems);
}

// --- OSV --------------------------------------------------------------------

class Finding {
  Finding(this.id, this.aliases, this.severity, this.summary);
  final String id;
  final List<String> aliases;
  final String severity;
  final String summary;
  final List<Component> components = [];
  ExceptionEntry? exception;

  bool get blocking => isBlocking(severity) && exception == null;

  /// `app-runtime` if any affected component is on the app runtime classpath,
  /// else `build-tooling` / `pub` / `unclassified`.
  String get scope {
    final scopes = components.map((c) => c.scope).toSet();
    for (final s in const ['app-runtime', 'pub', 'build-tooling']) {
      if (scopes.contains(s)) return s;
    }
    return 'unclassified';
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'aliases': aliases,
    'severity': severity,
    'scope': scope,
    'summary': summary,
    'blocking': blocking,
    'components': [for (final c in components) '${c.name}@${c.version}'],
    if (exception != null) 'exception': exception!.toJson(),
  };
}

abstract class OsvClient {
  /// For each component (same order), the OSV ids affecting it.
  Future<List<List<String>>> queryBatch(List<Component> components);
  Future<Map<String, Object?>> vulnerability(String id);
}

class HttpOsvClient implements OsvClient {
  HttpOsvClient({HttpClient? client})
    : _client = (client ?? HttpClient())
        ..connectionTimeout = const Duration(seconds: 30);
  final HttpClient _client;

  Future<Map<String, Object?>> _request(
    String method,
    String path, [
    Object? body,
  ]) async {
    Object? lastError;
    for (var attempt = 0; attempt < 4; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(Duration(seconds: 2 << attempt));
      }
      try {
        final req = await _client.openUrl(method, Uri.parse('$osvApi$path'));
        if (body != null) {
          req.headers.contentType = ContentType.json;
          req.write(jsonEncode(body));
        }
        final res = await req.close().timeout(const Duration(seconds: 60));
        final text = await utf8
            .decodeStream(res)
            .timeout(const Duration(seconds: 60));
        if (res.statusCode == 200) {
          return jsonDecode(text) as Map<String, Object?>;
        }
        lastError = 'HTTP ${res.statusCode}';
        if (res.statusCode != 429 && res.statusCode < 500) break;
      } on Object catch (e) {
        lastError = e;
      }
    }
    throw StateError('OSV request $method $path failed: $lastError');
  }

  @override
  Future<List<List<String>>> queryBatch(List<Component> components) async {
    final results = List<List<String>>.generate(components.length, (_) => []);
    const chunk = 500;
    for (var start = 0; start < components.length; start += chunk) {
      final slice = components.sublist(
        start,
        start + chunk > components.length ? components.length : start + chunk,
      );
      var pending = <int, String?>{
        for (var i = 0; i < slice.length; i++) i: null,
      };
      while (pending.isNotEmpty) {
        final indexes = pending.keys.toList();
        final response = await _request('POST', '/querybatch', {
          'queries': [
            for (final i in indexes)
              {
                'package': {
                  'name': slice[i].name,
                  'ecosystem': slice[i].ecosystem,
                },
                'version': slice[i].version,
                if (pending[i] != null) 'page_token': pending[i],
              },
          ],
        });
        final answers = response['results'];
        if (answers is! List || answers.length != indexes.length) {
          throw StateError('OSV querybatch returned a malformed response.');
        }
        final next = <int, String?>{};
        for (var n = 0; n < indexes.length; n++) {
          final answer = answers[n] as Map;
          final i = indexes[n];
          for (final v in (answer['vulns'] as List?) ?? const []) {
            results[start + i].add((v as Map)['id'] as String);
          }
          final token = answer['next_page_token'];
          if (token is String && token.isNotEmpty) next[i] = token;
        }
        pending = next;
      }
    }
    return results;
  }

  @override
  Future<Map<String, Object?>> vulnerability(String id) =>
      _request('GET', '/vulns/${Uri.encodeComponent(id)}');
}

class Assessment {
  Assessment({
    required this.commit,
    required this.generatedAt,
    required this.problems,
    required this.components,
    required this.findings,
    required this.expired,
    required this.snapshots,
    required this.lockfileSha256,
    required this.osvChecked,
  });

  final String commit;
  final DateTime generatedAt;
  final List<String> problems;
  final List<Component> components;
  final List<Finding> findings;
  final List<ExceptionEntry> expired;
  final List<Map<String, Object?>> snapshots;
  final String? lockfileSha256;
  final bool osvChecked;

  Verdict get verdict {
    if (problems.isNotEmpty || !osvChecked) return Verdict.incomplete;
    return findings.any((f) => f.blocking) ? Verdict.findings : Verdict.pass;
  }

  Map<String, Object?> toJson() => {
    'commit': commit,
    'generatedAt': generatedAt.toUtc().toIso8601String(),
    'verdict': verdict.name.toUpperCase(),
    'cleanResult': verdict == Verdict.pass,
    'problems': problems,
    'osvChecked': osvChecked,
    'counts': {
      'components': components.length,
      'gradle': components.where((c) => c.source == 'gradle').length,
      'pub': components.where((c) => c.source == 'pub').length,
      'findings': findings.length,
      'blocking': findings.where((f) => f.blocking).length,
    },
    'inputs': {
      'gradleSnapshots': snapshots,
      'pubspecLockSha256': lockfileSha256,
    },
    'findings': [for (final f in findings) f.toJson()],
    'expiredExceptions': [for (final e in expired) e.toJson()],
  };

  String toMarkdown() {
    final b = StringBuffer()
      ..writeln('# Dependency assessment')
      ..writeln()
      ..writeln('- Commit: `$commit`')
      ..writeln('- Generated: ${generatedAt.toUtc().toIso8601String()}');
    switch (verdict) {
      case Verdict.pass:
        b.writeln(
          '- **Result: PASS** — complete inventory, no unexcepted '
          'High/Critical/unrated advisories.',
        );
      case Verdict.findings:
        b.writeln(
          '- **Result: FINDINGS** — human triage required before release.',
        );
      case Verdict.incomplete:
        b.writeln(
          '- **Result: INCOMPLETE — this is NOT a clean result.** '
          'The inventory or advisory lookup did not complete.',
        );
    }
    b
      ..writeln(
        '- Components: ${components.length} '
        '(${components.where((c) => c.source == 'gradle').length} Maven/Gradle, '
        '${components.where((c) => c.source == 'pub').length} Pub)',
      )
      ..writeln();
    if (problems.isNotEmpty) {
      b.writeln('## Problems');
      for (final p in problems) {
        b.writeln('- $p');
      }
      b.writeln();
    }
    if (expired.isNotEmpty) {
      b.writeln('## Expired exceptions (not honored)');
      for (final e in expired) {
        b.writeln(
          '- ${e.advisory} / ${e.package} expired ${e.toJson()['expires']}',
        );
      }
      b.writeln();
    }
    if (findings.isNotEmpty) {
      b
        ..writeln('## Advisories')
        ..writeln()
        ..writeln('| Severity | Advisory | Scope | Components | Status |')
        ..writeln('| --- | --- | --- | --- | --- |');
      final ordered = [...findings]
        ..sort((a, b) => _rank(a.severity).compareTo(_rank(b.severity)));
      for (final f in ordered) {
        final status = f.exception != null
            ? 'excepted by ${f.exception!.approvedBy} until '
                  '${f.exception!.toJson()['expires']}'
            : f.blocking
            ? '**blocking**'
            : 'non-blocking';
        final comps = f.components
            .map((c) => '`${c.name}@${c.version}`')
            .join(', ');
        b.writeln(
          '| ${f.severity} | ${f.id} | ${f.scope} | $comps | $status |',
        );
      }
    }
    return b.toString();
  }
}

int _rank(String s) => switch (s) {
  'CRITICAL' => 0,
  'HIGH' => 1,
  'UNRATED' => 2,
  'MEDIUM' => 3,
  _ => 4,
};

/// Runs the full assessment. All I/O is injected so it can be unit tested.
Future<Assessment> assess({
  required String commit,
  required List<SnapshotInfo> snapshots,
  required String pubLockfile,
  String? pubLockfileSha256,
  required String? pluginsFile,
  required List<String> runtimeClasspaths,
  required String Function(String path) readGradleFile,
  required String? exceptionsContent,
  required OsvClient? osv,
  required DateTime now,
}) async {
  final problems = <String>[];

  if (snapshots.isEmpty) {
    problems.add('No Gradle dependency snapshot was provided.');
  }
  final components = <String, Component>{};
  for (final s in snapshots) {
    problems.addAll(
      validateSnapshot(s.json, expectedSha: commit, label: s.file),
    );
    for (final c in gradleComponents(s.json)) {
      components[c.key] = c;
    }
  }

  // Cross-check against Gradle's own view of the app runtime classpath, and
  // use it to tell shipped native libraries from build tooling.
  final runtime = <String>{};
  if (runtimeClasspaths.isEmpty) {
    problems.add(
      'No app runtime classpath supplied; cannot cross-check the snapshot '
      'against Gradle resolution.',
    );
  }
  for (final text in runtimeClasspaths) {
    final parsed = parseRuntimeClasspath(text);
    runtime.addAll(parsed.resolved);
    for (final f in parsed.failed) {
      problems.add('Gradle could not resolve $f on the app runtime classpath.');
    }
  }
  if (runtimeClasspaths.isNotEmpty && runtime.isEmpty) {
    problems.add('The supplied app runtime classpath lists no dependencies.');
  }
  if (snapshots.isNotEmpty) {
    problems.addAll(
      checkRuntimeClasspathCoverage(
        runtime: runtime,
        snapshotKeys: {
          for (final c in components.values) '${c.name}@${c.version}',
        },
      ),
    );
  }
  if (runtime.isNotEmpty) {
    for (final key in components.keys.toList()) {
      final c = components[key]!;
      components[key] = c.withScope(
        runtime.contains('${c.name}@${c.version}')
            ? 'app-runtime'
            : 'build-tooling',
      );
    }
  }

  final pub = parsePubLockfile(pubLockfile);
  if (pub.components.isEmpty) {
    problems.add('pubspec.lock lists no hosted Pub packages.');
  }
  for (final name in pub.unsupported) {
    problems.add('Pub package $name uses a git source; it cannot be checked.');
  }
  for (final c in pub.components) {
    components[c.key] = c;
  }

  if (pluginsFile == null) {
    problems.add(
      '.flutter-plugins-dependencies not found (run `make deps-lockfile`); '
      'cannot cross-check plugin Android dependencies against the snapshot.',
    );
  } else if (snapshots.isNotEmpty) {
    problems.addAll(
      checkPluginCoverage(
        pluginsFileContent: pluginsFile,
        snapshotCoordinates: {
          for (final c in components.values)
            if (c.source == 'gradle') c.name,
        },
        readGradleFile: readGradleFile,
      ),
    );
  }

  final exceptions = parseExceptions(exceptionsContent, now);
  problems.addAll(exceptions.problems);

  final findings = <Finding>[];
  var osvChecked = false;
  final list = components.values.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  if (osv == null) {
    problems.add('Advisory lookup was skipped (--offline); inventory only.');
  } else if (list.isNotEmpty) {
    try {
      final ids = await osv.queryBatch(list);
      final byId = <String, Finding>{};
      final records = <String, Map<String, Object?>>{};
      final unique = {for (final l in ids) ...l};
      final queue = unique.toList();
      Future<void> worker() async {
        while (queue.isNotEmpty) {
          final id = queue.removeLast();
          records[id] = await osv.vulnerability(id);
        }
      }

      await Future.wait([for (var i = 0; i < 8; i++) worker()]);
      for (var i = 0; i < list.length; i++) {
        for (final id in ids[i]) {
          final record = records[id]!;
          if (record['withdrawn'] != null) continue;
          final f = byId.putIfAbsent(
            id,
            () => Finding(
              id,
              [for (final a in (record['aliases'] as List?) ?? const []) '$a'],
              severityOf(record),
              '${record['summary'] ?? ''}',
            ),
          );
          f.components.add(list[i]);
        }
      }
      for (final f in byId.values) {
        for (final e in exceptions.active) {
          final matches =
              (e.advisory == f.id || f.aliases.contains(e.advisory)) &&
              f.components.any((c) => c.name == e.package);
          if (matches) f.exception = e;
        }
      }
      findings.addAll(byId.values);
      osvChecked = true;
    } on Object catch (e) {
      problems.add('Advisory lookup failed: $e');
    }
  }

  return Assessment(
    commit: commit,
    generatedAt: now,
    problems: problems,
    components: list,
    findings: findings,
    expired: exceptions.expired,
    snapshots: [
      for (final s in snapshots)
        {
          'file': s.file,
          'sha256': s.sha256Hex,
          'commit': s.json['sha'],
          'ref': s.json['ref'],
          'scanned': s.json['scanned'],
          'detector': s.json['detector'],
          'components': gradleComponents(s.json).length,
        },
    ],
    lockfileSha256: pubLockfileSha256,
    osvChecked: osvChecked,
  );
}

// --- CLI --------------------------------------------------------------------

Future<List<SnapshotInfo>> loadSnapshots(List<String> paths) async {
  final files = <File>[];
  for (final p in paths) {
    if (FileSystemEntity.isDirectorySync(p)) {
      files.addAll(
        Directory(p)
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.json')),
      );
    } else if (File(p).existsSync()) {
      files.add(File(p));
    }
  }
  files.sort((a, b) => a.path.compareTo(b.path));
  final out = <SnapshotInfo>[];
  for (final f in files) {
    final decoded = jsonDecode(f.readAsStringSync());
    if (decoded is Map<String, Object?>) {
      out.add(SnapshotInfo(f.path, sha256File(f.path), decoded));
    }
  }
  return out;
}

/// SHA-256 of a file via the platform tool (no package dependency needed).
String sha256File(String path) {
  for (final cmd in const [
    ['sha256sum'],
    ['shasum', '-a', '256'],
  ]) {
    try {
      final r = Process.runSync(cmd.first, [
        ...cmd.skip(1),
        path,
      ], stdoutEncoding: utf8);
      if (r.exitCode == 0) return (r.stdout as String).split(' ').first;
    } on ProcessException {
      continue;
    }
  }
  return '';
}

Never _usage(String message) {
  stderr
    ..writeln(message)
    ..writeln(
      'Usage: dart run tool/dependency_inventory.dart '
      '<validate-snapshot|assess> --sha <commit> '
      '--gradle-snapshot <file|dir> --runtime-classpath <file>... '
      '[--lockfile pubspec.lock] '
      '[--plugins-file apps/playground/.flutter-plugins-dependencies] '
      '[--exceptions .github/dependency-exceptions.json] [--out dir] [--offline]',
    );
  exit(64);
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) _usage('Missing command.');
  final command = args.first;
  if (command != 'validate-snapshot' && command != 'assess') {
    _usage('Unknown command "$command".');
  }
  final opts = <String, List<String>>{};
  var offline = false;
  for (var i = 1; i < args.length; i++) {
    final a = args[i];
    if (a == '--offline') {
      offline = true;
    } else if (a.startsWith('--') && i + 1 < args.length) {
      opts.putIfAbsent(a.substring(2), () => []).add(args[++i]);
    } else {
      _usage('Bad argument "$a".');
    }
  }
  String? one(String k) => opts[k]?.last;

  final sha = one('sha');
  if (sha == null || sha.isEmpty) _usage('--sha is required.');
  final snapshotPaths = opts['gradle-snapshot'] ?? const [];
  final snapshots = await loadSnapshots(snapshotPaths);
  final runtimeClasspaths = <String>[];
  for (final path in opts['runtime-classpath'] ?? const <String>[]) {
    final f = File(path);
    if (f.existsSync()) runtimeClasspaths.add(f.readAsStringSync());
  }

  if (command == 'validate-snapshot') {
    final problems = <String>[
      if (snapshots.isEmpty) 'No Gradle dependency snapshot found.',
      for (final s in snapshots)
        ...validateSnapshot(s.json, expectedSha: sha, label: s.file),
      if (runtimeClasspaths.isEmpty)
        'No app runtime classpath supplied (--runtime-classpath).'
      else
        ...checkRuntimeClasspathCoverage(
          runtime: {
            for (final t in runtimeClasspaths)
              ...parseRuntimeClasspath(t).resolved,
          },
          snapshotKeys: {
            for (final s in snapshots)
              for (final c in gradleComponents(s.json))
                '${c.name}@${c.version}',
          },
        ),
    ];
    if (problems.isEmpty) {
      stdout.writeln(
        'Snapshot OK: ${snapshots.length} file(s), '
        '${snapshots.expand((s) => gradleComponents(s.json)).length} components.',
      );
      return;
    }
    for (final p in problems) {
      stderr.writeln('::error::$p');
    }
    exit(2);
  }

  final lockfilePath = one('lockfile') ?? 'pubspec.lock';
  final pluginsPath =
      one('plugins-file') ?? 'apps/playground/.flutter-plugins-dependencies';
  final exceptionsPath =
      one('exceptions') ?? '.github/dependency-exceptions.json';
  final outDir = Directory(one('out') ?? 'dependency-evidence')
    ..createSync(recursive: true);

  final lockFile = File(lockfilePath);
  final plugins = File(pluginsPath);
  final exceptionsFile = File(exceptionsPath);
  final result = await assess(
    commit: sha,
    snapshots: snapshots,
    pubLockfile: lockFile.existsSync() ? lockFile.readAsStringSync() : '',
    pubLockfileSha256: lockFile.existsSync() ? sha256File(lockfilePath) : null,
    pluginsFile: plugins.existsSync() ? plugins.readAsStringSync() : null,
    runtimeClasspaths: runtimeClasspaths,
    readGradleFile: (path) {
      final f = File(path);
      return f.existsSync() ? f.readAsStringSync() : '';
    },
    exceptionsContent: exceptionsFile.existsSync()
        ? exceptionsFile.readAsStringSync()
        : null,
    osv: offline ? null : HttpOsvClient(),
    now: DateTime.now().toUtc(),
  );

  const encoder = JsonEncoder.withIndent('  ');
  File(
    '${outDir.path}/assessment.json',
  ).writeAsStringSync('${encoder.convert(result.toJson())}\n');
  File('${outDir.path}/assessment.md').writeAsStringSync(result.toMarkdown());
  File('${outDir.path}/inventory.json').writeAsStringSync(
    '${encoder.convert({
      'commit': sha,
      'components': [for (final c in result.components) c.toJson()],
    })}\n',
  );

  stdout.write(result.toMarkdown());
  for (final p in result.problems) {
    stderr.writeln('::error::$p');
  }
  exit(switch (result.verdict) {
    Verdict.pass => 0,
    Verdict.findings => 1,
    Verdict.incomplete => 2,
  });
}
