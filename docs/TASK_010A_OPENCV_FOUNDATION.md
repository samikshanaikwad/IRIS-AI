# TASK 010A — Android OpenCV foundation

Status: validated infrastructure only; TASK010 production matching is not implemented.

## Selected distribution

- Artifact: `org.opencv:opencv:4.10.0`
- Distribution: official OpenCV Android AAR from Maven Central
- Publisher: OpenCV Team / OpenCV.org
- Source: https://opencv.org/opencv4android-usage-models/
- Repository artifact: https://central.sonatype.com/artifact/org.opencv/opencv/4.10.0
- License declared by the artifact metadata: Apache-2.0
- Retrieval/validation date: 2026-09-28
- Android compatibility: AAR consumed through the existing Maven Central setup; IRIS `minSdk` remains 24.

The OpenCV team documents the Maven Central AAR as the maintained Android
distribution for applications that do not require contrib modules. The
dependency is added only to the Android module; no Flutter OpenCV wrapper is
introduced.

## Smoke coverage

`app/android/app/src/androidTest/kotlin/com/iris/incidentreconstruction/OpenCvRuntimeSmokeTest.kt`
uses controlled generated bitmaps only inside instrumentation tests. It
executes actual OpenCV operations for bitmap conversion, ORB keypoints and
descriptors, Hamming matching, fundamental-matrix estimation with RANSAC,
and a negative unrelated-image check. The test does not create production
matches, persistence, UI, or geometry.

The test passed on the Realme RMX3780 (Android 15/API 35). The app schema
remains v7 and no production feature-matching path was added.

## Build footprint

The debug APK produced after adding OpenCV was 473,853,200 bytes. A prior
baseline APK was not rebuilt during this prerequisite task, so an isolated
OpenCV-only byte delta is not claimed. The artifact is native and materially
large enough that release ABI/resource-splitting decisions should be reviewed
before production distribution.
