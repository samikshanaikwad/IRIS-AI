# TUMTraf-Accid3nD Acquisition Plan

**Research date:** 2026-09-27
**Scope:** TASK 006 planning only. No TUM archive, image, annotation, model, or
production-manifest item was acquired or created.

## Authoritative acquisition facts

The [Accid3nD project page](https://accident-dataset.github.io/) links its
dataset button to the public TUM storage share. A `HEAD`/WebDAV metadata query
on that official link found an unauthenticated collection named
`accid3nd_dataset` containing exactly these five published ZIP archives:

| Archive | Published bytes |
| --- | ---: |
| `train1.zip` | 9,436,619,494 |
| `train2.zip` | 9,436,522,698 |
| `train3.zip` | 9,436,612,632 |
| `train4.zip` | 9,435,983,723 |
| `train5.zip` | 8,841,778,208 |
| **Total** | **46,587,516,755** |

The public collection publishes no SHA-256 values, archive manifest, camera-only
archive, label-only archive, or independently downloadable LiDAR/calibration
component. Its internal ZIP trees and uncompressed size are therefore unknown
until a future authorized acquisition inspects them. IRIS must not guess those
details from generic TUMTraf releases.

The source-specific project describes 111,945 labeled frames, four roadside
cameras and LiDAR recorded at 25 Hz, 2,634,233 labels, OpenLABEL, collisions,
rollovers, and fires. It specifies four Basler ace acA1920-50gc cameras at
1920×1200 and 50 Hz plus one Valeo LiDAR. The supplement reports 12 sequences
observed by four roadside cameras. The [AccidentDet3D author repository](https://github.com/accident-dataset/AccidentDet3D)
also documents event extraction that writes each accident folder with images
from all four cameras. That supports grouping multiple views of one physical
event together; it is not evidence of the exact current archive-internal path
or field names.

The project says OpenLABEL includes 2D/3D boxes, masks, track IDs, and
trajectories. It does **not** publicly document a machine-readable ground-truth
collision/rollover/fire interval field for every archive item. A future
inspector must discover and record actual sequence, event, camera, timestamp,
frame, and scenario fields after authorized acquisition. There is no published
separate normal-driving subset. Accident-scene pre-event or quiet frames cannot
be accepted as `non_accident` merely because of timing; DATS remains the planned
negative source.

## Minimum download decision

The minimum currently published official download is all five `train*.zip`
archives: **46,587,516,755 bytes** (about 46.59 GB decimal, 43.39 GiB). The
official inventory does not permit downloading camera imagery independently of
LiDAR, point clouds, calibration, maps, or other packaged modalities. A future
acquisition may extract only RGB camera images plus the corresponding OpenLABEL
metadata into IRIS's ignored working area, but it must retain the verified raw
archives until inspection is reproducible. It must not silently obtain an
unofficial partial mirror or use HTTP ranges to invent a camera-only subset.

The expected grouping scale is **12 published sequences**, not a confirmed
count of physical accidents. A sequence may contain a physical accident and
multiple camera views; exact event count remains `UNKNOWN` until the actual
metadata is inspected.

## Licence gate

The source-specific project page states CC BY-NC-SA 4.0. The official generic
TUMTraf development-kit README instead states CC BY-NC-ND 4.0 for TUMTraf data.
This conflict has direct consequences:

- Under CC BY-NC-SA, derived still datasets would need attribution, a licence
  link, change marking, non-commercial use, and ShareAlike for adaptations.
- Under CC BY-NC-ND, extracting/repackaging stills may be an impermissible
  adaptation; IRIS must not assume it is allowed.
- Neither source separately settles whether a trained classifier or TFLite file
  is an adaptation or how it may be distributed.

Before download, request source-specific written confirmation from TUM covering
the governing licence for `accid3nd_dataset`, local still extraction for
academic training, source/derived-media redistribution, and trained-model/TFLite
distribution. Preserve the received answer, required attribution, licence text,
and any change notice in the source registry. Until then the source remains
`REVIEW_REQUIRED`.

## Proposed deterministic extraction policy (not executed)

These are engineering parameters to validate after inspecting the actual
archive; they are not scientific thresholds or claimed dataset facts.

1. Use `tumtraf-accid3nd:<physical_event_id>` as the fundamental group when a
   real event identifier exists. Otherwise use the complete sequence identifier
   as the conservative group. Every camera, timestamp, and derived still from
   that group remains in one split.
2. Retain the original archive path, archive SHA-256 (computed after download),
   source image path, source image SHA-256, dHash, sequence/event ID, camera ID,
   timestamp/frame ID, and annotation path. Never alter source image bytes.
3. Use published scenario metadata only to propose review windows. A human
   reviewer decides each still as `accident`, `exclude_ambiguous`, or another
   allowed evidence decision. Pre-impact and imminent-only frames are excluded.
4. Record `collision_visible` and `aftermath_only` as distinct review evidence.
   Accept collision-visible images when the still independently supports the
   label. Default aftermath-only images to exclusion unless the still clearly
   depicts accident-damaged road-vehicle context and the reviewer records that
   basis.
5. Initial review sampling parameter: one candidate per camera per 25 labeled
   frames (approximately one second at the published 25 Hz), maximum two
   collision-visible candidates per camera and event. This caps a fully usable
   four-camera event at eight candidates before SHA-256/dHash filtering and
   human exclusion. It is a review-efficiency cap, not a prediction of yield.
6. With 12 published sequences, the policy has a theoretical pre-review cap of
   96 selected source images. Actual usable positives remain `UNKNOWN` until
   real visual review and duplicate checks complete.
7. Run exact SHA-256 and dHash duplicate analysis before splitting. Merge any
   duplicate/near-duplicate component into its source-event group; reject any
   cross-split component. Never split by frame.

## DATS negative-review plan

The existing tooling already creates a bounded, byte-verified batch from the
2,850 pending DATS images without changing the master inventory. It copies only
the selected source bytes to ignored local batch storage, verifies each copied
SHA-256 against the inventory, and creates `review_batch.csv`. This task adds a
local `review_sheet.html` contact sheet to each batch. It shows the copied
images, original source identifier, SHA-256, and `pending` state only; it never
creates a label.

Recommended review loop: make batches of 100, open `review_sheet.html`, record
observed decisions/rationale/reviewer/date in `review_batch.csv`, apply the
batch, then run `validate-reviews`. Human interaction is required for every
accepted or excluded semantic decision. The conservative DATS source groups and
the existing exact/dHash leakage controls remain unchanged.
