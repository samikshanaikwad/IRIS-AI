# Evidence Acquisition and Integrity

TASK 004 introduces real, local evidence acquisition. It does not perform accident classification, analysis, reconstruction, or any other AI function.

## Database schema

Database schema version 2 adds `evidence_images`. Each record belongs to a row in `cases` through a foreign key with `ON DELETE CASCADE`. Records contain a stable ID, case ID, managed relative path, optional original display name, `camera` or `gallery` source, optional known capture time, IRIS import time, optional media type and pixel dimensions, byte size, and the full SHA-256 digest. A unique `(case_id, sha256)` constraint prevents exact-byte duplicates inside one case, while allowing the same bytes in different cases.

Migration from version 1 creates only the evidence table and index. It does not delete or rewrite existing case rows. Migration is rejected if the required version 1 cases table is missing.

## Managed storage

Evidence originals are copied to the application-support directory under this relative structure:

```text
iris/
  cases/
    <case-id>/
      evidence/
        <evidence-id>.<validated-extension>
```

Case and evidence IDs are validated before constructing paths. Original names never determine the managed filename. Relative paths containing traversal components or absolute paths are rejected. Files are copied through streams to a `.part` file and renamed only after copying succeeds. The source bytes are not resized, recompressed, annotated, or otherwise modified. Future processing must use derivatives rather than overwrite these originals.

## Import and integrity behavior

Imports are independently atomic per selected item. IRIS copies one source, computes SHA-256 from the managed copy, reads only metadata available from that file/API, and then inserts its database record. A database failure removes the copied file. A copy or hash failure creates no row. Multi-image partial success is reported as real imported, duplicate, and failed counts.

Exact duplicate detection uses SHA-256 only and is scoped to the case. A duplicate managed copy is removed and the existing evidence record is retained. SHA-256 is an integrity identifier; IRIS does not present it as proof of legal chain of custody.

## Permissions and source APIs

Camera access uses the Flutter `camera` plugin and is invoked only after the user selects Take Photo. The Android manifest declares `CAMERA`; the plugin requests access at the point of use. Denied, restricted, unavailable-camera, initialization, and capture failures are shown as unavailable/error states and never as successful captures.

Gallery access uses `image_picker` for one or multiple real images and explicitly enables the Android system Photo Picker where the implementation supports it. It requests no broad Android storage permission and no location permission. Cancellation makes no changes. IRIS does not infer EXIF or incident location in this task.

## Deletion consistency

Evidence removal first renames the managed file to an IRIS-controlled pending-deletion path. The row is then deleted. A database failure restores the file; success finalizes file deletion. Case deletion uses the same staging pattern for the validated, IRIS-owned case directory, then deletes the case row (which cascades evidence rows), restores the directory on database failure, and finalizes directory deletion on success. Other case directories are never targeted.

## Android plugin registration

The production `MainActivity` continues to invoke Flutter's generated plugin registrant explicitly. The build guard verifies generated metadata for CameraX, image picker, path provider, and sqflite and verifies generated registrant entries for native Flutter plugins. Debug-only MainActivity diagnostics report whether camera, image picker, sqflite, and the JNI backend used by path provider are packaged and registered on that exact engine. Android integration also calls `getApplicationSupportDirectory()` and `getDatabasesPath()` through the production engine.

## Current limitations

- Full EXIF and GPS extraction are intentionally deferred.
- Originals are app-private but no export or chain-of-custody workflow exists yet.
- Deterministic technical image quality checks are documented in [EVIDENCE_QUALITY.md](EVIDENCE_QUALITY.md). AI analysis, reconstruction, physics, scenarios, and reports are not implemented.
