# TASK012I evidence-to-scene diagnosis

## Physical observation and repository interpretation

The user reported the existing Realme case displaying 22 buildings, zero trees,
zero barriers, zero proxies, current quality/classification/relative geometry,
completed detection, analyzed depth, and **World alignment: not saved**.
These are user-observed counts, not automated device measurements for this revision.

`SqliteWorldAlignmentRepository.get(evidenceId)` returns null only when the query
for that evidence ID has no row. It does not filter stale rows. The scene's
`not saved` label therefore means missing, not a rejected stale transform.
Existing rows with changed geometry/road fingerprints take a separate stale path.
Schema migrations do not delete alignments; evidence/case deletion has dependent
cleanup. There is no alignment audit history, so absence cannot prove whether an
alignment was never saved, belonged to other evidence, or was previously deleted.
No historical alignment is resurrected.

The physical-case anchor generation was blocked before sampling. Eligible class
counts and point counts must be read from the new status-only diagnostics; they
must not be guessed from the classifier or earlier evidence descriptions.

## Applicability contract retained

Saved TASK012B transforms use uniform scale, then Y-axis yaw, then XYZ translation.
Their source is USER_SUPPLIED. The stored road fingerprint includes case ID,
confirmed origin, road status and serialized road geometry. It is not a separable
origin-only version. Removing it would silently permit a transform in a changed
world frame. Current cached same-location road context remains required.
Live Overture/Overpass success and building availability are not prerequisites.
No schema change (v15), transform migration, inference rerun, or provider change.

## Explicit eligibility and action

Every evidence item is evaluated independently. Detection, depth, geometry,
alignment and world states are retained separately, with a deterministic primary
blocking reason. Geometry inspection reads the repository and verifies source
timestamp/SHA, artifact checksum, bounded point count, coordinate version and
finite XYZ/normalized UV without regenerating anything.

Sources & evidence exposes **Align Evidence N** for readable current geometry
and current roads. It opens the existing user-controlled editor. Cancel preserves
the prior database record; Save Alignment is the only write. On return the scene
reloads repositories, reevaluates all evidence, rebuilds render data and resets
the camera. It does not refresh providers or run inference.

## Detection and anchor audit

TASK007 outputs normalized coordinates in the padded 320-square model frame.
TASK009C UV coordinates are normalized in its padded 518-square depth frame.
Both native inputs apply the same supported EXIF rotations and preserve aspect
ratio; resize rounding differs by subpixel amounts. There is no proven current
case coordinate-rejection failure. No speculative remapping/fallback was added.

Eligible IDs/labels: 1 bicycle, 2 car, 3 motorcycle, 5 bus, 7 truck; score >=0.30,
finite ordered normalized boxes. Production service also validates source SHA,
model hash and frozen policy. Anchor remains a real geometry sample at median
relative Z inside the box's inner X20–80%, Y50–90% region. No valid sample means
no anchor. No road snapping, origin fallback, camera pose or metric depth.
Bounding-box/background uncertainty remains because segmentation is unavailable.

## Display changes and verification boundary

Vehicle anchors drive initial/reset framing; absence falls back to the incident
location environment view. Motorcycle has two low-poly wheels, body/tank/seat,
engine, raked fork and swingarm; bicycle uses wheels and triangular frame beams.
Cars retain body/cabin/wheels; bus/truck have distinct generic display silhouettes
and materials. These are display-only proportions, not dimensions or heading.
Existing real road surfaces, Overture buildings, face shading/occlusion and
Scene/Analysis layer controls remain intact. No environment features are added.

Automated coverage includes source states, all-evidence evaluation, real-box
sampling, geometry artifact inspection, user save/cancel/reload, class meshes,
camera priority and existing renderer behavior. Physical post-save appearance
requires the user to explicitly place and save the evidence on the Realme.

Manual steps: same case -> Open 3D Reconstruction -> Sources & evidence ->
Align Evidence 1 -> adjust Move X / Move Z / Heading / Scale as user-supplied
placement -> Save Alignment. The scene recomputes on return. Do not rerun valid
depth/detection/geometry or refresh the working environment merely to align.

Diagnostics contain ordinal evidence numbers, states and counts only. No database
export, precise coordinates, source paths or image contents are needed.
