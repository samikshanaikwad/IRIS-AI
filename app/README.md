# IRIS Flutter Application

This directory contains the Android-focused Flutter application for IRIS.

The current application implements the dark design system, reusable interface components, navigation shell, and an offline SQLite case-metadata lifecycle. User-confirmed cases can be created, listed, opened, renamed, and deleted. Home and Cases read the same repository state; a clean database remains truthfully empty and storage failures render an error state.

The database is named `iris.db`, currently uses schema version 1, and contains no production seeds. Evidence acquisition, incident analysis, and reconstruction capabilities are not implemented yet.

Run from this directory with the documented Flutter, Android SDK, and JDK 17 toolchain:

```powershell
flutter run
flutter analyze
flutter test
flutter build apk --debug
```
