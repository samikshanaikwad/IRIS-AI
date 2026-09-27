# Local classification source data

This directory is reserved for acquired source datasets. Its contents are
ignored by Git except for this documentation and `.gitkeep`.

Do not place IRIS user evidence here. Do not add data unless its provenance,
content usage terms, and task suitability have been reviewed.

The planned DoTA layout is:

```text
dota/
  official_repository/
    dataset/
      DoTA_annotations.zip
      annotations/
      metadata_train.json
      metadata_val.json
      DoTA_urls.txt
  official_frames/
    frames/
      <source_event_id>/
        images/
          000000.jpg
```

The source registry remains authoritative for acquisition and usage status.
DoTA extraction remains blocked until dataset-content and derived-frame use are
approved and both normal and collision-visible review windows are populated.
