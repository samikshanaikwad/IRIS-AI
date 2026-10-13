# TASK012J — professional reconstruction visualization

## Recovery and engineering decision

TASK012I was preserved and committed separately as `584caf9`. The user reported
physical verification of the same case: 22 buildings, one motorcycle scene object,
1687 relative points and current explicit alignment. These are user observations,
not hard-coded application expectations. No inference, alignment or provider
pipeline is rebuilt by TASK012J. SQLite stays v15; no dependencies are added.

Decision: retain the renderer-independent ReconstructionScene and current
CustomPainter backend for bounded V0. It already supports arbitrary XYZ faces,
camera-space perspective, near clipping, polygon holes, deterministic far-first
ordering, multiple evidence vehicles, picking and cached mesh construction.
The identified problems are bounded display problems, not missing 3D primitives.
This does not assert equivalence to a GPU depth buffer: intersecting/cyclic faces
can still exhibit painter-order artifacts. A larger future scene or demonstrated
unacceptable mobile frame timing would justify a depth-buffered backend behind
the same domain model. No second production renderer is introduced here.

## Camera and clipping

Vehicle anchors determine the incident region. A nearest real road segment within
40 local units contributes a quarter-weight viewing-target offset and bounded
context extent. This is a camera decision only, never road snapping. Without
vehicles the confirmed origin and environment fallback remain available.

After the first physical acceptance round exposed a giant-foreground-wall view,
 initial/reset orientation evaluates 48 deterministic candidates (16 yaws, three
bounded oblique elevations). The earlier eye-inside-footprint and single
eye-to-target-ray checks were insufficient: a camera outside a building could
still devote much of the screen to a near wall. Candidate scoring now also uses
a fixed virtual viewport to penalize projected building coverage in the central
region and direct coverage of the evidence anchor, retain the evidence in a
useful central screen region, and reward visible projected length from genuine
nearby road segments. The incident span is bounded from vehicle/near-road context,
not the complete provider radius. Buildings and evidence are never removed or
moved to obtain a clear view. Source heights are used when available; otherwise
the same representational display height as the renderer is used.

## Round 3 road visibility diagnostics

TASK012J.1 records count-only render diagnostics after the scene has painted:
source road count, centerline segments, near-evidence proximity bucket, generated
ribbon pieces/faces, source-width versus representational-width counts, submitted
road faces, clipped/projected road faces, top ribbon faces in the viewport and
whether an evidence anchor projects into the viewport. No coordinates, image paths,
provider payloads or case exports are emitted. This distinguishes a missing source
road from ribbon generation, clipping/frustum, or presentation failures on the
physical device.

Road top faces use a display-only offset above the visualization reference plane
and a restrained outline to prevent depth ambiguity. The offset, material and edge
are not pavement elevation, real asphalt colour, lane markings, curbs or source
road attributes. Initial framing reserves a bounded amount of genuine nearest-road
extent around a vehicle and has a slight display-only downward look target to reduce
empty sky; it never moves the analytical evidence anchor.

Faces clip in camera space against the near plane and four viewport planes.
Non-finite source/camera inputs do not produce projected paths. Pitch and pinch
are bounded; pinch updates use the gesture's baseline, not cumulative multiplication.
Building walls are subdivided for more local depth ordering. Large-face average
depth remains a documented V0 limitation, not an analytical occlusion result.
Reference ground and coplanar road underlays draw before depth-sorted volumes,
so coarse tile centroids cannot cover roads/building bases. The reference plane
is intentionally not an occluding terrain measurement.

## Source appearance audit and feasibility

The OSM parser retains original tags. The Overture decoder retains all properties
provided by its selected PMTiles building layer. No property stripping was found
in those paths; whether the upstream layer supplies appearance for a particular
building is a separate question. No new provider query or source replacement is
required. Current-case appearance counts have NOT been inferred from the 22
building total. Sources & evidence exposes them after that case is loaded:

- buildings total;
- valid explicit wall colors;
- valid explicit roof colors;
- nonempty building/roof material attributes;
- valid explicit source heights;
- buildings using UNKNOWN_NEUTRAL on either wall or roof (each counted once).

The debug bridge emits the same count-only `stage=appearance` record. It contains
no coordinates, evidence paths or image data. Unavailable source context is not
described as verified zero coverage.

`SurfaceAppearance` distinguishes MAP_DERIVED and UNKNOWN_NEUTRAL; the enum reserves
EVIDENCE_OBSERVED but no production extraction/assignment path creates that state.
Supported source keys are `building:colour` and `roof:colour`. A bounded set of
CSS names plus opaque #RGB/#RRGGBB is accepted; malformed, alpha, multi-value and
ambiguous text is rejected. Material names never imply a color or texture.
Original values/tags and provider remain persisted. Environment JSON also records
normalized base color/provenance when written; older records derive identical
validated appearance from their existing tags without a schema migration.
Roof and wall attributes remain separate. Display lighting never overwrites them.

**EVIDENCE-TO-BUILDING APPEARANCE ASSOCIATION NOT YET RELIABLE.** Relative monocular
geometry and a user placement are not solved camera extrinsics or a building-surface
correspondence. TASK007 vehicle boxes do not segment façades. The smallest genuine
next capability is explicit evidence-region-to-mapped-surface association with
visibility validation; automatic association would require stronger camera/world
correspondence and building/scene segmentation. Segmentation alone does not solve
registration. No evidence pixels were sampled or applied to arbitrary buildings.
TASK012K could address that separately; it is not started here. Unseen surfaces
remain neutral unless a map source independently establishes their appearance.

## Display geometry and UI

- Ground is a finite, incident-bounded neutral reference platform, not terrain
  or land cover/provider coverage extent.
  Only top tiles and the perimeter are generated; internal slab walls are omitted.
- Road surfaces contrast the ground. Real centerlines/explicit widths remain
  unchanged; absent width continues as a labeled representational ribbon. No
  lane markings, sidewalks, curbs or extra roads are generated.
- Building rings normalize repeated closure/winding for display without changing
  source vertices. Roof holes are retained. Explicit height stays map-derived;
  absent height uses the same fixed representational extrusion, never random height.
  Roof form remains a simple display cap, not inferred architecture. Unknown
  wall/roof appearance retains UNKNOWN_NEUTRAL provenance while deterministic
  neutral base tones, face shading and restrained edges improve spatial reading;
  none are persisted as source appearance.
- Motorcycle has two visible wheels/hubs, tapered tank, body, seat, fork and
  handlebar suggestion. Other class silhouettes remain distinct. A bounded
  viewport-readable display scale acts about the unchanged analytical anchor.
  Its pivot is at the proxy wheel base; elevation/heading/dimensions are not measured.
- Incident reference is a thin ring, explicitly not a collision object/point.
- Deterministic ambient/directional face lighting provides depth cues. It does
  not estimate accident illumination, sun direction, weather or time of day.
- Scene View defaults technical overlays off; Analysis View can show point
  geometry, centerlines and grid. Sources & evidence is collapsed by default.
  Fullscreen hides the source panel and mode chips, retaining compact exit/reset,
  picking and gestures; camera/layer state is retained. No view toggle writes
  analytical data.

## TASK012J.2 canonical world-frame audit

The production audit found no separate road/evidence world transform. Both the
alignment preview and ReconstructionScene consume persisted TASK011
`localCoordinates` and the same TASK012B transform. The canonical contract is:

- origin: confirmed TASK011 incident location;
- X: east, Y: up, Z: north;
- map units: accepted TASK011 local metres;
- evidence transform order: user uniform scale, positive yaw around +Y, then
  user X/Y/Z translation;
- TASK009C source geometry remains relative, normalized and uncalibrated.

The first visual divergence was the alignment preview's independent 2D
auto-fit: it centers and normalizes the entire road query plus point cloud,
whereas Scene View uses an incident-focused perspective camera and its vehicle
diagnostic measures the detection-derived anchor. Auto-fit screen proximity is
not a metric relationship. The preview now says so explicitly and shows the
canonical incident-origin ring. No persisted alignment or source geometry is
rewritten, migrated, or snapped to a road.

`CaseLocalWorldFrame` is the single named conversion boundary used for the
accepted TASK011 geographic conversion and TASK012B transform. Safe diagnostics
report separate buckets for the vehicle anchor and complete aligned point
geometry, plus `canonicalFrame=ready`; they contain no coordinates or paths.

## Acceptance boundary

Automated tests include color validation/provenance, legacy serialization,
obstruction candidates, framing, invalid projection/clipping, source-preserving
mesh construction, symbolic incident reference, stable gestures and fullscreen
state. A controlled fixture image may be generated ONLY by the test runner with
`IRIS_RENDER_QA=true`; it is never loaded into a user case or shipped as source data.

Realme visual acceptance and current-case appearance counts require opening the
same existing case after deployment. Do not recreate the case, rerun inference,
change location or recreate the saved alignment. Open 3D Reconstruction -> Scene
View; check orbit/zoom/reset/fullscreen, then Sources & evidence for appearance
counts. No claim of physical acceptance or overall TASK012 completion is made.
# Stable alignment provenance (TASK012J.3)

Schema v16 adds nullable `world_frame_fingerprint` and
`provenance_version` fields to saved evidence/world alignments. New or
explicitly reconfirmed placements bind to the stable confirmed-location
canonical frame (`case id + confirmed origin + frame-contract version`) and
the evidence-geometry SHA-256. Mutable road-provider content remains recorded
as historical context but does not invalidate a v2 placement when roads are
added, reordered, or refreshed at the same confirmed location.

Legacy records are not rewritten. An exact current road-snapshot fingerprint
can prove continued applicability; a mismatch cannot prove that the original
location was unchanged and therefore requires explicit review in Align
Evidence. Review preserves the saved translation, yaw, and scale unless the
user changes them. No evidence is snapped to a road.
