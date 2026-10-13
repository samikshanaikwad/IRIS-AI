# TASK012 reconstruction checkpoint and implementation-readiness audit

## Scope and checkpoint basis

This audit records the reviewed TASK012J, J.1, J.2 and J.3 working tree
before later evidence-faithful reconstruction work begins.  It is not a claim
of physical visual acceptance or forensic reconstruction completeness.

The reviewed work upgrades the database to schema v16, establishes a named
canonical local-world boundary, makes user alignments robust to mutable road
provider content, and improves the existing lightweight 3D presentation. It
does not alter original evidence, re-run inference, alter a saved alignment's
translation/yaw/scale, or create analytical data from display meshes.

## Current production data flow

```
managed original evidence bytes + SHA-256
  -> classification / EfficientDet-Lite0 detections / Depth Anything V2 depth
  -> TASK009C relative XYZUV point artifact
  -> optional TASK010 ORB/F-matrix correspondence
  -> explicit TASK012B scale -> yaw -> translation
  -> ReconstructionScene -> CustomPainter render primitives
```

`EvidenceStorage` retains the original image bytes. The detector persists
normalized model-canvas boxes; depth produces a padded 518-square relative
depth map; TASK009C samples it into at most 2,048 points with XYZ and UV.
The resulting geometry is relative and uncalibrated, not a metric mesh.

`EvidenceVehicleMarker` samples real geometry from the lower-central detection
region, and only then applies the saved user transform. It does not snap to a
road, infer heading, metric dimensions, a collision point, or a trajectory.
`ReconstructionSceneService` evaluates all evidence items rather than only the
first one, and renderer input is separate from analytical records.

## Appearance and damage finding

The source image is retained, but its appearance is lost at the current
TASK009C -> scene boundary:

* `RelativePoint` stores only `x`, `y`, `z`, `u`, and `v`; there is no RGB,
  segmentation mask, topology, material, texture, or damage annotation.
* `scene_render_data.dart` turns a class/anchor into a fixed, procedural,
  representational mesh with display colours. It has no image or mask input.
* No bundled production instance-segmentation or damage-localisation model is
  present. Existing classifier, detector, depth, and ORB implementations do
  not provide either capability.

Therefore a clean blue motorcycle proxy is a class marker, not a reconstruction
of the observed black/orange motorcycle or visible front-end damage. It must
remain labelled representational until an evidence-derived partial surface is
available. Visible image colour also represents illumination/exposure and is
not automatically intrinsic paint colour.

## Map and coordinate finding

The persisted TASK011 incident origin is the local-world origin. The current
contract is X east, Y up, Z north. `CaseLocalWorldFrame` now makes the map
conversion and evidence alignment boundary explicit. User transforms preserve
the established operation order: uniform scale, positive yaw around Y, then
X/Y/Z translation.

Schema v16 adds nullable stable world-frame provenance to alignments. New or
explicitly reconfirmed records bind geometry SHA-256 plus a case/confirmed-origin
frame fingerprint. A road refresh, reordering, or additional roads no longer
invalidates such a placement. A legacy record with only a changed road snapshot
cannot establish its original frame and remains review-required; it is never
silently resurrected. Translation, yaw, and scale are never rewritten.

The shared geographic conversion currently uses a fixed eastward scale factor
(`111320 * .999`) rather than latitude-aware longitude scaling. It is shared
by road and building conversion, so it is not the earlier divergent-view bug,
but it is not a geodetically robust tangent frame. A future correction requires
a versioned canonical-frame upgrade and deterministic compatibility treatment
for saved placements and cached local coordinates. It must not be silently
changed.

The Align Evidence preview can make road/evidence look close because it uses a
separate fit-to-view display transform. That screen-space proximity is not a
metric statement and must not be used to move evidence.

## Existing renderer and visual limitations

The current CustomPainter renderer supports genuine X/Y/Z vertices, perspective,
camera-space clipping, far-first face ordering, shallow road/ground slabs,
low-poly building extrusion and procedural vehicle proxies. It is deliberately
lightweight, but has no depth buffer: intersecting or cyclic surfaces can have
painter-order artifacts. Road surfaces use genuine centerlines and either an
explicit source width or a labelled representational ribbon width.

The reference ground is a bounded display platform, not terrain. Its extent,
material, building heights without source values, roof caps, mesh proportions,
face lighting, and unknown-neutral building tone are display choices. They are
not persisted as observations. Scene framing is incident-oriented when a valid
anchor exists, but a valid user alignment may still place evidence far from
map roads; that is not evidence of a measured distance and must not cause road
snapping. Scene and Analysis modes expose the distinction between display and
technical layers.

OSM roads and Overture building footprints retain provider provenance. Overture
feature retrieval is bounded and cache/applicability scoped. Feature counts use
provider/source identity to avoid duplicate fragment counts. Missing map features
remain absent; no decorative surroundings are generated.

## Implementation plan

### Phase A — evidence-derived partial representation

1. Add a versioned, shared original-image <-> detector canvas <-> depth canvas
   coordinate contract, including every EXIF orientation/mirror case and exact
   resize/padding metadata. Preserve existing artifacts; make new derivatives
   explicitly versioned.
2. Qualify, rather than assume, an Android-capable instance/object segmentation
   model. Qualification must cover licences, immutable model hash, native/Dart
   parity, damaged examples and car/motorcycle/bus/truck/bicycle performance on
   the RMX3780. Box-prompted MobileSAM ONNX is a candidate to evaluate, not an
   approved production dependency. Until qualified, report segmentation
   unavailable or use an explicitly user-authored mask only if such a workflow
   is intentionally added.
3. Persist an evidence-derived mask artifact with source SHA, model/version or
   user provenance, orientation/coordinate contract and integrity hash. Never
   generate a mask from a class label alone.
4. Build a partial coloured surfel/triangulated surface only from mask-covered,
   observed depth pixels. Preserve observed pixels and silhouette/damage
   appearance; do not fill unseen/back faces, bridge invalid depth holes, or
   claim dent depth. Use the accepted user transform only after relative-space
   construction.
5. Treat learned damage localisation as a separate qualification. Image colour
   and visible damaged shape can be represented in a partial surface before a
   reliable damage-category/dimension model exists. Unknown damage stays
   unknown.

Reuse `relative_geometry_service.dart`, `evidence_vehicle_marker.dart`,
`reconstruction_scene.dart`, and `scene_render_data.dart`; add a bounded
evidence-appearance artifact/service and a renderer primitive behind the scene
domain. The first acceptance gate is a damaged and an intact real evidence
image yielding different partial appearances, with no fabricated unseen mesh.

### Phase B — real surroundings and defensible integration

1. Retain case-scoped `CaseLocationService`, road context, environment context,
   OSM and Overture provider provenance/caches. Retrieve independently; a
   supplemental outage must not erase a valid cached provider result.
2. Version and migrate the local tangent-frame calculation before replacing the
   east-scale approximation. Establish deterministic old/new frame handling for
   local map caches and saved alignment provenance first.
3. Maintain explicit evidence eligibility: evidence identity, current geometry
   provenance, valid stable world-frame alignment and numerical transform. Do
   not require photo-visible surroundings, but never derive placement solely
   from selected location or road proximity.
4. Render only retrieved roads, footprints, explicitly mapped trees/barriers,
   and source height where supplied. Represent unknown heights and widths
   separately from map-derived facts.

Acceptance: two locations return independently cached, provenance-labelled map
context; map failure is not reported as verified absence; evidence remains
unsnapped and its alignment is explicitly user supplied.

### Phase C — professional low-poly presentation

1. Keep map geometry analytical and create a stable display-palette layer keyed
   by source identity. Source colour is used only when valid; otherwise a
   deterministic stylised palette is labelled visualization, not observed
   appearance. Roof/wall materials remain independent.
2. Add explicit Evidence Focus and Location Overview camera modes. Score true
   projected coverage using the actual viewport aspect, include nearby real
   road/building context only when it exists, and keep reset deterministic.
3. Improve road/ground contrast, joins and face shading without inventing lanes,
   curbs, trees, or buildings. Profile the present painter before any GPU/back
   end change; only introduce a depth-buffered renderer if measured occlusion
   or interaction performance cannot meet the target.
4. Render evidence-derived partial surfaces preferentially; keep a category
   proxy only as a clearly marked fallback. Do not treat display scale,
   orientation or lighting as forensic measurement.

Acceptance: roads and map volumes are legible in overview; evidence is large
enough in focus view; Analysis View keeps point geometry available; source vs
stylised appearance is visible in provenance; no generic proxy is presented as
damage-faithful.

### Phase D — physical Android acceptance

Run the complete suite and model validators, then test on the RMX3780 with
multiple independent real evidence images (including different classes,
orientations and damaged/intact examples) and at least two confirmed locations.
Check per-case cache isolation, restart/offline reopening, provider failure,
alignment review, focus/overview camera, orbit/pan/zoom/reset and memory/frame
timing. Proposed performance budgets must be measured before becoming release
criteria; no current test establishes a device frame-time budget.

Physical acceptance must establish different source images lead to different
evidence-derived appearances where qualified, real locations lead to their own
map context, uncertain features stay labelled, and the installed app—not only
the test harness—visually passes review.

## Current blockers and first executable milestone

The first executable milestone is **Phase A1: image-coordinate contract plus
segmentation qualification harness**. It is deliberately a qualification task,
not a production model integration: choose/obtain a legally usable model,
benchmark it on the target device, validate coordinate alignment against the
existing detector/depth transforms, and reject it if it cannot produce reliable
class-appropriate masks. Only a passed qualification permits a production mask
artifact and coloured partial surface.

Open blockers: no approved instance segmentation or damage model; no calibrated
camera/intrinsics or metric depth; no source-based visible-damage geometry; no
versioned geodetic frame migration; painter-only occlusion/performance has not
been physically accepted. None may be hidden by a generic intact vehicle mesh.
