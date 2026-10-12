// Tests for tool/dependency_inventory.dart. Plain `dart` (no test package, so
// the workspace lockfile is untouched): run with `make test-tools`.
import 'dart:io';

import 'dependency_inventory.dart';

int _failures = 0;
int _passed = 0;

void expectTrue(bool condition, String name) {
  if (condition) {
    _passed++;
  } else {
    _failures++;
    stderr.writeln('FAIL: $name');
  }
}

void expectEq(Object? actual, Object? expected, String name) {
  expectTrue(actual == expected, '$name (got $actual, expected $expected)');
}

const sha = '7345fa5620bc9455a743e73131f926b69584b1e9';

Map<String, Object?> snapshot({
  String? commit = sha,
  int count = 120,
  List<String> extra = const [
    'pkg:maven/com.android.tools.build/gradle@9.0.1?repository_url=x',
    'pkg:maven/org.jetbrains.kotlin/kotlin-gradle-plugin@2.3.20',
    'pkg:maven/io.flutter/flutter_embedding_release@1.0.0-abc',
    'pkg:maven/androidx.webkit/webkit@1.15.0',
  ],
}) {
  return {
    'version': 0,
    'sha': commit,
    'scanned': '2026-10-12T00:00:00Z',
    'manifests': {
      'm': {
        'resolved': {
          for (var i = 0; i < count; i++)
            'g:a$i:1': {'package_url': 'pkg:maven/g/a$i@1'},
          for (final p in extra) p: {'package_url': p},
        },
      },
    },
  };
}

class FakeOsv implements OsvClient {
  FakeOsv(this.vulns, {this.fail = false});
  final Map<String, Map<String, Object?>> vulns;
  final bool fail;

  @override
  Future<List<List<String>>> queryBatch(List<Component> components) async {
    if (fail) throw StateError('network down');
    return [
      for (final c in components)
        if (vulns.isNotEmpty && c.name == 'androidx.webkit:webkit')
          ['GHSA-test']
        else
          <String>[],
    ];
  }

  @override
  Future<Map<String, Object?>> vulnerability(String id) async => vulns[id]!;
}

const lockfile = '''
packages:
  clock:
    dependency: "direct main"
    description:
      name: clock
      sha256: abc
      url: "https://pub.dev"
    source: hosted
    version: "1.1.3"
  flutter:
    dependency: "direct main"
    description: flutter
    source: sdk
    version: "0.0.0"
  local_thing:
    dependency: "direct main"
    description:
      path: "../x"
      relative: true
    source: path
    version: "1.0.0"
sdks:
  dart: ">=3.12.0 <4.0.0"
''';

Future<void> main() async {
  // purl parsing
  final c = componentFromPurl(
    'pkg:maven/androidx.webkit/webkit@1.15.0?repository_url=https%3A%2F%2Fdl.google.com',
  )!;
  expectEq(c.name, 'androidx.webkit:webkit', 'purl name');
  expectEq(c.version, '1.15.0', 'purl version');
  expectTrue(componentFromPurl('pkg:npm/left-pad@1.0.0') == null, 'non-maven');
  expectTrue(componentFromPurl('pkg:maven/nogroup') == null, 'malformed purl');

  // pub lockfile: hosted only, sdk/path skipped
  final pub = parsePubLockfile(lockfile);
  expectEq(pub.components.length, 1, 'hosted pub package count');
  expectEq(pub.components.single.name, 'clock', 'hosted pub package');
  expectEq(pub.components.single.version, '1.1.3', 'hosted pub version');

  // snapshot validation: good, stale, empty, too small, missing canary
  expectEq(validateSnapshot(snapshot(), expectedSha: sha).length, 0, 'valid');
  expectTrue(
    validateSnapshot(
      snapshot(commit: 'deadbeef'),
      expectedSha: sha,
    ).any((p) => p.contains('stale')),
    'stale sha rejected',
  );
  expectTrue(
    validateSnapshot({
      'sha': sha,
      'scanned': 'x',
      'manifests': <String, Object?>{},
    }, expectedSha: sha).any((p) => p.contains('no manifests')),
    'empty manifests rejected',
  );
  expectTrue(
    validateSnapshot(
      snapshot(count: 3),
      expectedSha: sha,
    ).any((p) => p.contains('empty or partial')),
    'too few components rejected',
  );
  expectTrue(
    validateSnapshot(
      snapshot(extra: const ['pkg:maven/androidx.webkit/webkit@1.15.0']),
      expectedSha: sha,
    ).any((p) => p.contains('missing required coordinate')),
    'missing canary rejected',
  );

  // runtime classpath parsing
  const tree = '''
releaseRuntimeClasspath - Runtime classpath of '/release'.
+--- org.jetbrains.kotlin:kotlin-stdlib:2.3.20
|    +--- org.jetbrains:annotations:13.0 -> 23.0.0
|    +--- org.jetbrains.kotlin:kotlin-stdlib-jdk8:1.8.0 (c)
|    \\--- org.jetbrains.kotlin:kotlin-stdlib-jdk7:1.8.0 (c)
+--- project :connectivity_plus
|    +--- androidx.core:core:1.18.0
|    \\--- androidx.collection:collection -> 1.4.2 (*)
\\--- com.example:broken:1.0 FAILED
''';
  final rt = parseRuntimeClasspath(tree);
  expectTrue(
    rt.resolved.contains('org.jetbrains.kotlin:kotlin-stdlib@2.3.20'),
    'rt direct',
  );
  expectTrue(
    rt.resolved.contains('org.jetbrains:annotations@23.0.0'),
    'rt arrow',
  );
  expectTrue(
    rt.resolved.contains('androidx.collection:collection@1.4.2'),
    'rt versionless',
  );
  expectTrue(
    !rt.resolved.any((r) => r.contains('jdk8')),
    'rt skips constraints',
  );
  expectEq(rt.failed.single, 'com.example:broken', 'rt failed node');
  expectEq(
    checkRuntimeClasspathCoverage(
      runtime: {'a:b@1', 'c:d@2'},
      snapshotKeys: {'a:b@1'},
    ).length,
    1,
    'runtime coverage gap detected',
  );

  // plugin coverage
  const plugins =
      '{"plugins":{"android":[{"name":"p","path":"/p/","native_build":true}]}}';
  String gradle(String path) =>
      'dependencies { implementation("androidx.webkit:webkit:1.15.0")\n'
      '  testImplementation("junit:junit:4.13.2")\n'
      '  classpath("com.android.tools.build:gradle:\$v") }';
  expectEq(
    checkPluginCoverage(
      pluginsFileContent: plugins,
      snapshotCoordinates: {'androidx.webkit:webkit'},
      readGradleFile: gradle,
    ).length,
    0,
    'plugin deps covered (test deps and variables ignored)',
  );
  expectTrue(
    checkPluginCoverage(
      pluginsFileContent: plugins,
      snapshotCoordinates: {},
      readGradleFile: gradle,
    ).any((p) => p.contains('androidx.webkit:webkit')),
    'plugin dep missing from graph detected',
  );
  expectTrue(
    checkPluginCoverage(
      pluginsFileContent: '{"plugins":{"android":[]}}',
      snapshotCoordinates: {},
      readGradleFile: gradle,
    ).isNotEmpty,
    'no android plugins is a problem',
  );

  // severity
  expectEq(
    cvssV3Score('CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H'),
    9.8,
    'cvss 9.8',
  );
  expectEq(
    cvssV3Score('CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:C/C:H/I:H/A:H'),
    10.0,
    'cvss 10',
  );
  expectEq(
    severityOf({
      'database_specific': {'severity': 'MODERATE'},
    }),
    'MEDIUM',
    'moderate is medium',
  );
  expectEq(
    severityOf({
      'severity': [
        {
          'type': 'CVSS_V3',
          'score': 'CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H',
        },
      ],
    }),
    'CRITICAL',
    'cvss fallback',
  );
  expectEq(severityOf({}), 'UNRATED', 'no data is unrated');
  expectTrue(isBlocking('UNRATED'), 'unrated blocks');
  expectTrue(!isBlocking('MEDIUM'), 'medium does not block');

  // exceptions
  final now = DateTime.utc(2026, 10, 12);
  final ex = parseExceptions('''
{"exceptions": [
  {"advisory":"GHSA-test","package":"androidx.webkit:webkit","reason":"r","approvedBy":"@a","expires":"2026-12-01"},
  {"advisory":"GHSA-old","package":"p","reason":"r","approvedBy":"@a","expires":"2026-01-01"},
  {"advisory":"GHSA-far","package":"p","reason":"r","approvedBy":"@a","expires":"2030-01-01"},
  {"advisory":"GHSA-incomplete"}
]}''', now);
  expectEq(ex.active.length, 1, 'one active exception');
  expectEq(ex.expired.length, 1, 'one expired exception');
  expectEq(ex.problems.length, 2, 'too-far and incomplete rejected');
  expectTrue(parseExceptions('{', now).problems.isNotEmpty, 'bad JSON flagged');

  // end-to-end verdicts
  final snap = SnapshotInfo('s.json', 'x', snapshot());
  final runtimeText = '+--- androidx.webkit:webkit:1.15.0\n';
  Future<Assessment> run({
    OsvClient? osv,
    String? exceptions,
    String? commit,
    List<String>? runtimeTexts,
  }) => assess(
    commit: commit ?? sha,
    snapshots: [snap],
    pubLockfile: lockfile,
    pluginsFile: plugins,
    runtimeClasspaths: runtimeTexts ?? [runtimeText],
    readGradleFile: gradle,
    exceptionsContent: exceptions,
    osv: osv,
    now: now,
  );
  final high = {
    'GHSA-test': {
      'id': 'GHSA-test',
      'summary': 's',
      'database_specific': {'severity': 'HIGH'},
    },
  };

  final clean = await run(osv: FakeOsv({}));
  expectEq(
    clean.verdict,
    Verdict.pass,
    'clean inventory passes ${clean.problems}',
  );

  final found = await run(osv: FakeOsv(high));
  expectEq(found.verdict, Verdict.findings, 'high advisory -> findings');
  expectEq(
    found.findings.single.scope,
    'app-runtime',
    'finding scoped to app runtime',
  );

  final excepted = await run(
    osv: FakeOsv(high),
    exceptions:
        '{"exceptions":[{"advisory":"GHSA-test","package":"androidx.webkit:webkit","reason":"r","approvedBy":"@a","expires":"2026-12-01"}]}',
  );
  expectEq(excepted.verdict, Verdict.pass, 'active exception unblocks');
  expectTrue(
    excepted.findings.single.exception != null,
    'exception stays visible',
  );

  final down = await run(osv: FakeOsv({}, fail: true));
  expectEq(down.verdict, Verdict.incomplete, 'lookup failure is incomplete');
  expectEq(down.toJson()['cleanResult'], false, 'incomplete is never clean');

  final offline = await run(osv: null);
  expectEq(offline.verdict, Verdict.incomplete, 'offline is incomplete');

  final stale = await run(osv: FakeOsv({}), commit: 'f' * 40);
  expectEq(stale.verdict, Verdict.incomplete, 'stale snapshot is incomplete');

  final noRuntime = await run(osv: FakeOsv({}), runtimeTexts: const []);
  expectEq(
    noRuntime.verdict,
    Verdict.incomplete,
    'missing runtime classpath is incomplete',
  );

  final gap = await run(
    osv: FakeOsv({}),
    runtimeTexts: ['+--- not.in:snapshot:1.0\n'],
  );
  expectEq(
    gap.verdict,
    Verdict.incomplete,
    'graph/Gradle mismatch is incomplete',
  );

  stdout.writeln('$_passed passed, $_failures failed');
  if (_failures > 0) exit(1);
}
