# TASK012 master reconstruction recovery

Baseline: `dc806f075f52f2fb6ae419727405bb80dca4e3ed`. This continues the interrupted
working tree; accepted history, models, original evidence and saved alignments
are not reset. Physical acceptance remains outstanding.

## Interrupted-work audit

| Recovered area | Initial classification | Completed work |
| --- | --- | --- |
| EnvironmentProvider, bounded HTTP, Overture PMTiles | Partial / live diagnostic qualified | Retained; independent requests, defensive budgets, geographic filtering, provenance and tests |
| Source snapshots / SQLite v15 | Partial | Non-destructive migration, serialized sources, atomic same-location save, restart/cache tests |
| CaseLocationService / composition | Partial | Provider isolation, cached-data retention, fixed self-awaiting refresh cleanup, explicit refresh |
| ReconstructionScene / loader | Partial, missing import | Renderer-independent scene, all-evidence prerequisites, current-source reads, current alignment checks |
| Render data / painter | Incomplete / unused, shading syntax error | Completed and connected; near-plane clipping, depth ordering, mesh inspection |
| Road scene viewer | Old architecture still active | Replaced internal analytical rediscovery with scene consumer; fixed pinch baseline and refresh repaint |
| Multi-view repository | Partial integration | Current verified relationships surfaced without camera pose, fusion or vehicle identity claims |
| Qualification tool | Development diagnostic | Retained outside application graph; no persistence or database access |

## Real providers and dependencies

- Official Overture catalog: https://stac.overturemaps.org/catalog.json (`latest`).
- Official building tiles: `https://overturemaps-extras-us-west-2.s3.us-west-2.amazonaws.com/tiles/<release>/buildings.pmtiles`.
- Source references: https://docs.overturemaps.org/examples/overture-tiles/,
  https://docs.overturemaps.org/getting-data/cloud-sources/,
  https://docs.overturemaps.org/attribution/.
- Pin `pmtiles` 1.3.0 (BSD-2-Clause) and `vector_tile` 2.0.0 (MIT): compatible
  with the existing Dart 3.9/protobuf constraints. No Flutter/GPU/game engine.
  Upstream: https://github.com/bramp/pmtiles-dart and
  https://github.com/bahung1221/dart-vector-tile.
- Building geometry is official **z14 inspection-tile geometry**: clipped,
  quantized, not full-precision survey data. Original GERS ID, release, tags,
  sources metadata and optional height are preserved. Fragments count once by
  source ID, while keeping distinct tile-part geometry. Missing tiles mean no
  coverage; missing/failed archives are errors, not empty buildings.
- Overture: +/-150 m geographic bounding box; intersecting footprints retained.
  Maximum nine tiles, 12 MiB transfer, 2 MiB decoded tile, 2,000 fragments and
  1,000 source IDs. Range requests must receive HTTP 206. No global download.
- OSM supplemental: 150 m `around` query, building ways/simple relations,
  tree nodes, wall/fence/guard-rail ways, `out tags geom`.
  Primary `overpass-api.de`; one delayed fallback `overpass.private.coffee`.
  Bounded 4 MiB per endpoint, 20-second request/stream timeouts. Public endpoints
  require capacity/usage review before larger-scale deployment.
- Dependencies are local decoders. Network only retrieves user-requested public
  map data; original images and other case data are not uploaded.

## Persistence and resilience

Schema **14 -> 15** only adds `environment_contexts.sources_json`, default `[]`.
Legacy feature rows remain readable. Each provider stores latest request state,
attempt time, last usable retrieval time, release, endpoint, structured geographic
and local geometry, original source tags, stable IDs and whether cached.

Location is loaded inside the app from the existing confirmed TASK011 repository.
No current-device-location substitution. No external database extraction.
Provider calls run independently. A failed provider retains its last usable
same-location snapshot; it cannot erase another provider. A successful empty
result is distinct from failure. Refresh save transaction rejects a changed or
deleted location; reopening filters incompatible old contexts. Existing road
cache is also retained on failed same-location saves.

Overture footprints take building-layer precedence when nonempty; OSM still
provides trees/barriers and supplies buildings when Overture has no usable
footprints. This is explicit source precedence, **not** guessed building identity
or completeness. Full source snapshots remain persisted. Complex OSM relations
are unsupported rather than filled incorrectly; only a single closed outer way
without inner/additional rings is accepted. Missing height does not reject a
valid footprint. Missing path vertices do not create invented connecting edges.

## Scene and analytical safety

`ReconstructionSceneService` composes one renderer-independent snapshot with roads,
environment, every evidence item's prerequisites, applicable relative geometry,
saved alignment, detections and current verified multi-view relationships.
It does not rerun models or regenerate geometry. A confirmed origin can retrieve
buildings without roads. Evidence placement still requires current road context.

Saved TASK012B transforms remain scale -> Y yaw -> translation. Relative geometry
is never automatically metric. TASK007 currentness is checked by the existing
detection service; eligible anchors use the accepted deterministic lower-central
box/median-depth sample. No segmentation or exact 3D vehicle dimensions. Each
detection retains its evidence identity. Separate views are not automatically
deduplicated into a shared vehicle, triangulated, or fused by TASK010.

TASK011's established local conversion is deliberately preserved:
`X=(longitude-originLongitude)*111320*0.999`, `Z=(latitude-originLatitude)*111320`,
Y up. This is a legacy approximate frame, **not a rigorous tangent projection**;
east/west distortion increases away from the equator. Correcting it later needs
versioning and explicit review of accepted alignments. Query coverage uses
geographic latitude-dependent bounds independently of this display frame.

Render-only classes hold vertices, faces and meshes, never SQLite evidence.
Source height produces a map-derived building extrusion; absent height uses a
labelled display extrusion. Road widths use explicit valid source width or a
labelled display ribbon. Road/ground thickness, tree/barrier proportions, vehicle
silhouettes and neutral orientation are representational. No physical dimensions
may be inferred from these meshes by future physics. Ground is not terrain.

CustomPainter remains the lightweight renderer: cached mesh construction,
perspective camera, orbit/pitch/pan, near-plane clipping, deterministic far-first
face ordering, interleaved aligned evidence points. Finite ground tiles and road
subdivision reduce painter overlap artifacts. This is not a pixel Z-buffer;
intersecting polygons/tile seams can still show ordering artifacts. No claim of
measured illumination, roof design, terrain, collision location or exact pose.

Scene View defaults to surfaces/volumes, technical overlays off. Analysis View
exposes evidence points, road centerlines and grid independently. Environment has
its own toggle. Tap a mesh for provenance; Sources & evidence lists per-provider
state/cache/release and each evidence item's missing prerequisites. Reset and
double tap reset restore incident-focused framing. Pinch uses one gesture-start
zoom baseline. A new scene snapshot always triggers repaint.

## Qualification and physical acceptance

`app/tool/qualify_overture.dart` is a public development control, never imported by
the app and has no repository/storage handle. It validates the production decoder
against live data. It cannot attach control features to a user case. See final
delivery report for the final control counts, test/build/deployment results.

Current-case counts must come from **the user's existing persisted location** via
the production refresh. Debug logs expose source/scene counts and source-height
counts, not coordinates, image paths, hashes or unrelated case records.

Manual steps after in-place deployment:

1. Open the existing accepted case, then **Open 3D Reconstruction**.
2. Tap **Refresh mapped environment**; inspect source statuses, counts, cache
   timestamps, actual building volumes and all evidence prerequisites.
3. Orbit/pinch/reset, inspect the motorcycle proxy if current prerequisites exist,
   and toggle evidence/centerlines/grid in Analysis View.
4. Reopen without refresh (including offline) to check stored source data.

The user chose to perform this later. No current-case building counts, rendered
appearance, device FPS or physical manual acceptance are claimed from tests.

### Verified delivery results (2026-10-03)

- Final live public control: Overture release `2026-09-23.1`, **246** unique
  footprints/fragments, **10** source heights, **236** unknown heights,
  **536,981 bytes** transferred. Earlier 150-footprint result used the narrower
  legacy-frame filter; the final decoder uses geographic +/-150 m bounds.
- Focused tests: **24 passed**. Full Flutter suite: **125 passed**. The first full
  run exposed the old migration test's literal schema-14 expectation; it now
  checks the current schema and new column while retaining preservation checks.
- `flutter analyze --no-fatal-infos`: exit 0, 16 pre-existing informational lint
  diagnostics, no errors/warnings. `git diff --check`: pass.
- TASK007/TASK009 contract validators: pass. Exact SHA-256 values unchanged:
  depth `f983ac210c302d37e0c07b075575426a4694a2b6eed6414fe66339bcb75a6830`;
  detector `2e04c53bfeac0ac2a30c057c7e2a777594ce39baaac35a92f74fb1e8c4fc4e0b`.
- Debug APK: build successful, **473,853,320 bytes**, using installed Gradle
  `:app:assembleDebug --no-daemon --max-workers=2`. No contention, cache deletion,
  process termination or Flutter clean. Existing SDK/deprecation warnings remain.
- Realme `65S4D65L85AIOFOR`: `adb install -r` succeeded; launch returned `Status: ok`,
  app process alive and MainActivity resumed. Original first-install timestamp
  retained. No uninstall, app clear, database export or evidence regeneration.
- Phone schema initialization was not observable in the filtered device logs;
  migration preservation is verified by automated tests, not by exporting data.
  Current-case provider counts, actual scene appearance and offline device reopen
  remain manual acceptance checks. No source-count claim is made for that case.
