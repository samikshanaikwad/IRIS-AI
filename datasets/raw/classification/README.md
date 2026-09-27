# Local classification source data

This directory is reserved for acquired source datasets. Its contents are
ignored by Git except for this documentation and `.gitkeep`.

Do not place IRIS user evidence here. Do not add data unless its provenance,
content usage terms, and task suitability have been reviewed.

Current ignored source layouts are:

```text
accident_detection_9k/v2/
  Accident_Detection.zip
  README.md
  annotation_guidelines.pdf
  data.yaml

dats_2022/v2/
  DATS_2022.zip
  inventory/

review_batches/
  <review batch>/
```

The AccidentDetection archive is publisher-annotated candidate data, not an
automatically accepted positive set. Every DATS image is an unlabelled
road-scene candidate until human review. Review batches may contain extracted
source images and therefore remain ignored.

The preserved future DoTA layout is:

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
Its approximately 55 GB frame archive has not been downloaded.
