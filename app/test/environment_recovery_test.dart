import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:iris/features/location/data/bounded_http_client.dart';
import 'package:iris/features/location/data/environment_provider.dart';
import 'package:iris/features/location/data/overpass_environment_provider.dart';
import 'package:iris/features/location/data/overture_environment_provider.dart';
import 'package:iris/features/location/data/sqlite_case_location_repository.dart';
import 'package:iris/features/location/application/case_location_service.dart';
import 'package:iris/features/location/domain/case_location.dart';
import 'package:iris/features/location/domain/environment_context.dart';
import 'package:iris/features/location/domain/environment_composition.dart';
import 'package:iris/features/location/domain/environment_parser.dart';
import 'package:iris/features/evidence/data/evidence_storage.dart';
import 'package:iris/core/database/migrations/database_migrations.dart';
import 'package:iris/core/database/database_constants.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vector_tile/raw/raw_vector_tile.dart' as raw;
import 'support/case_test_harness.dart';

CaseLocation location(String id, [double latitude = 0]) => CaseLocation(
  caseId: id,
  latitude: latitude,
  longitude: 0,
  source: CaseLocationSource.mapSelection,
  updatedAt: DateTime.utc(2026),
);
const building = EnvironmentFeature(
  id: 'source/tile',
  sourceId: 'source',
  provider: 'Overture Maps',
  sourceRelease: 'test-release',
  elementType: 'tile_polygon',
  featureType: 'building',
  coordinates: [
    [0, 0],
    [0, .0001],
    [.0001, .0001],
  ],
  localCoordinates: [
    [0, 0],
    [11.12, 0],
    [11.12, 11.132],
  ],
  tags: {},
);
EnvironmentSourceSnapshot snapshot(
  String name,
  EnvironmentProviderState state, [
  List<EnvironmentFeature> features = const [],
]) => EnvironmentSourceSnapshot(
  provider: name,
  state: state,
  attemptedAt: DateTime.utc(2026),
  retrievedAt: state.isSuccess ? DateTime.utc(2026) : null,
  features: features,
  release: 'test-release',
);

class TestProvider implements EnvironmentProvider {
  TestProvider(this.name, this.response);
  @override
  final String name;
  EnvironmentSourceSnapshot response;
  final List<CaseLocation> calls = [];
  bool fail = false;
  @override
  Future<EnvironmentSourceSnapshot> fetch(CaseLocation p) async {
    calls.add(p);
    if (fail) throw const FormatException('test decoder failure');
    return response;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'bounded client rejects full archive response and excessive transfer',
    () async {
      final ignored = BoundedHttpClient(
        inner: MockClient((_) async => http.Response('full', 200)),
      );
      await expectLater(
        ignored.get(
          Uri.parse('https://example.test'),
          headers: {'Range': 'bytes=0-5'},
        ),
        throwsA(isA<http.ClientException>()),
      );
      ignored.close();
      final huge = BoundedHttpClient(
        inner: MockClient((_) async => http.Response('123456', 200)),
        maxBytes: 5,
      );
      await expectLater(
        huge.get(Uri.parse('https://example.test')),
        throwsA(isA<http.ClientException>()),
      );
      huge.close();
    },
  );
  test(
    'Overpass retries independently; failure, parse error and empty differ',
    () async {
      for (final pair in [
        (504, 'timeout', EnvironmentProviderState.httpError),
        (200, 'invalid', EnvironmentProviderState.parseError),
        (
          200,
          '{"remark":"runtime error"}',
          EnvironmentProviderState.overpassError,
        ),
        (200, '{"elements":[]}', EnvironmentProviderState.successEmpty),
      ]) {
        var requests = 0;
        final provider = OverpassEnvironmentProvider(
          delay: Duration.zero,
          clientFactory: () => MockClient((r) async {
            requests++;
            expect(r.body, contains('around%3A150%2C0.0%2C0.0'));
            return http.Response(pair.$2, pair.$1);
          }),
        );
        final result = await provider.fetch(location('test'));
        expect(result.state, pair.$3);
        expect(result.features, isEmpty);
        expect(requests, pair.$3.isSuccess ? 1 : 2);
      }
    },
  );
  test(
    'production tile decoder preserves stable IDs, source height, source geometry',
    () {
      // Synthetic MVT only in tests. A closed square near z14 tile origin.
      for (final height in [false, true]) {
        final bytes = raw
            .createVectorTile(
              layers: [
                raw.createVectorTileLayer(
                  name: 'building',
                  extent: 4096,
                  version: 2,
                  keys: ['id', 'height', 'sources'],
                  values: [
                    raw.createVectorTileValue(stringValue: 'fixture-id'),
                    raw.createVectorTileValue(doubleValue: 12),
                    raw.createVectorTileValue(stringValue: 'fixture-source'),
                  ],
                  features: [
                    raw.createVectorTileFeature(
                      type: raw.VectorTile_GeomType.POLYGON,
                      tags: [
                        0,
                        0,
                        2,
                        2,
                        if (height) ...[1, 1],
                      ],
                      geometry: [9, 20, 20, 26, 40, 0, 0, 40, 39, 0, 15],
                    ),
                  ],
                ),
              ],
            )
            .writeToBuffer();
        final result = parseOvertureTile(
          bytes,
          8192,
          8192,
          14,
          location('test'),
          'fixture-release',
        );
        expect(result, hasLength(1));
        expect(result.single.sourceId, 'fixture-id');
        expect(result.single.tags['sources'], 'fixture-source');
        expect(result.single.sourceHeight, height ? 12 : isNull);
        expect(
          result.single.localCoordinates.first,
          localMetricPoint(
            result.single.coordinates.first[0],
            result.single.coordinates.first[1],
            0,
            0,
          ),
        );
        expect(
          EnvironmentFeature.fromJson(result.single.toJson()).sourceRelease,
          'fixture-release',
        );
      }
    },
  );
  test('tile buffer clipping is bounded and deterministic', () {
    const ring = [
      [-2.0, -2.0],
      [2.0, -2.0],
      [2.0, 2.0],
      [-2.0, 2.0],
    ];
    expect(clipRing(ring, -1, -1, 1, 1), clipRing(ring, -1, -1, 1, 1));
    expect(
      clipRing(ring, -1, -1, 1, 1).expand((p) => p).every((v) => v.abs() <= 1),
      isTrue,
    );
  });
  test('valid same-location cache survives independent provider outage', () {
    final p = location('test');
    final old = composeEnvironment(p, [
      snapshot('Overture Maps', EnvironmentProviderState.successWithFeatures, [
        building,
      ]),
    ], null);
    final next = composeEnvironment(p, [
      snapshot('Overture Maps', EnvironmentProviderState.httpError),
      snapshot('OpenStreetMap', EnvironmentProviderState.httpError),
    ], old);
    expect(next.count('building'), 1);
    expect(next.hasVerifiedResult, isTrue);
    expect(next.sources.first.cached, isTrue);
    expect(next.sources.first.state, EnvironmentProviderState.httpError);
    expect(next.sources.first.retrievedAt, old.sources.first.retrievedAt);
    expect(
      composeEnvironment(location('test', 1), [
        snapshot('Overture Maps', EnvironmentProviderState.httpError),
      ], old).hasVerifiedResult,
      isFalse,
    );
  });
  test(
    'successful empty source remains zero; no synthesized trees or vehicles',
    () {
      final result = composeEnvironment(location('test'), [
        snapshot('Overture Maps', EnvironmentProviderState.successEmpty),
      ], null);
      expect(result.count('building'), 0);
      expect(result.count('tree'), 0);
      expect(result.features, isEmpty);
      expect(result.providerState, EnvironmentProviderState.successEmpty);
    },
  );
  test('empty Overture does not erase real supplemental buildings', () {
    final osm = EnvironmentFeature.fromJson({
      ...building.toJson(),
      'provider': 'OpenStreetMap',
    });
    final result = composeEnvironment(location('test'), [
      snapshot('Overture Maps', EnvironmentProviderState.successEmpty),
      snapshot('OpenStreetMap', EnvironmentProviderState.successWithFeatures, [
        osm,
      ]),
    ], null);
    expect(result.count('building'), 1);
    expect(result.features.single.provider, 'OpenStreetMap');
  });
  test(
    'v14 to v15 preserves all existing tables and legacy environment rows',
    () async {
      sqfliteFfiInit();
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await migrateDatabase(db, 0, 14);
      await db.insert('cases', {
        'id': 'c',
        'title': 'Case',
        'status': 'draft',
        'created_at': 1,
        'updated_at': 1,
      });
      await db.insert('environment_contexts', {
        'case_id': 'c',
        'provider': 'OpenStreetMap',
        'retrieved_at': 1,
        'status': 'AVAILABLE',
        'features_json': jsonEncode([building.toJson()]),
        'latitude': 0,
        'longitude': 0,
        'provider_state': 'SUCCESS_WITH_FEATURES',
      });
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      );
      final before = {
        for (final t in tables) t['name']: await db.query(t['name']! as String),
      };
      await migrateDatabase(db, 14, 15);
      for (final t in tables) {
        final name = t['name']! as String;
        final after = await db.query(name);
        expect(after.length, before[name]!.length);
        for (var i = 0; i < after.length; i++) {
          for (final entry in before[name]![i].entries) {
            expect(after[i][entry.key], entry.value);
          }
        }
      }
      expect(
        (await db.query('environment_contexts')).single['sources_json'],
        '[]',
      );
      expect(IrisDatabaseConstants.schemaVersion, 15);
    },
  );
  test(
    'persisted location drives query; restart/cache/location applicability and isolation',
    () async {
      final h = await CaseTestHarness.create();
      addTearDown(h.dispose);
      final c = await h.repository.createCase(title: 'Fixture');
      final repo = SqliteCaseLocationRepository(h.database);
      final overture = TestProvider(
        'Overture Maps',
        snapshot(
          'Overture Maps',
          EnvironmentProviderState.successWithFeatures,
          [building],
        ),
      );
      final osm = TestProvider(
        'OpenStreetMap',
        snapshot('OpenStreetMap', EnvironmentProviderState.httpError),
      );
      CaseLocationService service() => CaseLocationService(
        repository: repo,
        storage: EvidenceStorage(rootProvider: () async => h.directory),
        environmentProviders: [overture, osm],
      );
      expect(await service().refreshEnvironment(c.id), isNull);
      expect(overture.calls, isEmpty);
      await repo.save(location(c.id));
      final result = await service().refreshEnvironment(c.id);
      expect(overture.calls.single.source, CaseLocationSource.mapSelection);
      expect(overture.calls.single.latitude, 0);
      expect(result!.count('building'), 1);
      await h.database.close();
      expect((await service().loadEnvironment(c.id))!.count('building'), 1);
      overture.fail = true;
      expect((await service().refreshEnvironment(c.id))!.count('building'), 1);
      expect(
        (await repo.getEnvironmentContext(c.id))!.sources.first.cached,
        isTrue,
      );
      await repo.save(location(c.id, 1));
      expect(await service().loadEnvironment(c.id), isNull);
      expect(await repo.saveApplicableEnvironment(result), isFalse);
      final changed = await service().refreshEnvironment(c.id);
      expect(overture.calls.last.latitude, 1);
      expect(changed!.hasVerifiedResult, isFalse);
      expect(changed.features, isEmpty);
    },
  );
}
