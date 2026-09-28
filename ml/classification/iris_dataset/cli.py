from __future__ import annotations

import argparse
import csv
import json
import sys
from pathlib import Path
from typing import Sequence

from .dota import inspect_dota_metadata
from .extraction import (
    extract_dota_frames,
    load_category_policy,
    load_extraction_policy,
    load_normal_windows,
    load_visible_windows,
)
from .image_tools import ImageDependencyError
from .manifest import (
    DatasetConfigurationError,
    load_manifest,
    load_source_registry,
    write_manifest,
)
from .mendeley import (
    SourceInspectionError,
    apply_review_batch,
    apply_review_batches_atomically,
    create_review_batch,
    inspect_mendeley_sources,
    load_review_inventory,
    validate_review_batch,
    validate_review_inventory,
)
from .reporting import build_report, format_report
from .splitting import assign_group_splits, load_split_policy
from .validation import validate_dataset

REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
DEFAULT_MANIFEST = (
    REPOSITORY_ROOT / "datasets/manifests/classification/manifest.v1.csv"
)
DEFAULT_REGISTRY = (
    REPOSITORY_ROOT / "datasets/manifests/classification/source_registry.v1.json"
)
DEFAULT_DATA_ROOT = REPOSITORY_ROOT / "datasets/derived/classification"
DEFAULT_EXTRACTION_POLICY = (
    REPOSITORY_ROOT / "ml/classification/configs/extraction_policy.v1.json"
)
DEFAULT_CATEGORY_POLICY = (
    REPOSITORY_ROOT / "ml/classification/configs/dota_category_policy.v1.json"
)
DEFAULT_SPLIT_POLICY = (
    REPOSITORY_ROOT / "ml/classification/configs/split_policy.v1.json"
)
DEFAULT_VISIBLE_WINDOWS = (
    REPOSITORY_ROOT
    / "datasets/manifests/classification/dota_visible_windows.v1.csv"
)
DEFAULT_NORMAL_WINDOWS = (
    REPOSITORY_ROOT
    / "datasets/manifests/classification/dota_normal_windows.v1.csv"
)
DEFAULT_ACCIDENT_ARCHIVE = (
    REPOSITORY_ROOT
    / "datasets/raw/classification/accident_detection_9k/v2/Accident_Detection.zip"
)
DEFAULT_DATS_ARCHIVE = (
    REPOSITORY_ROOT / "datasets/raw/classification/dats_2022/v2/DATS_2022.zip"
)
DEFAULT_DATS_INVENTORY = (
    REPOSITORY_ROOT / "datasets/raw/classification/dats_2022/v2/inventory"
)
DEFAULT_ACCIDENT_REVIEW = (
    REPOSITORY_ROOT
    / "datasets/manifests/classification/accident_detection_9k_review.v1.csv"
)
DEFAULT_DATS_REVIEW = (
    REPOSITORY_ROOT / "datasets/manifests/classification/dats_2022_review.v1.csv"
)
DEFAULT_MENDELEY_INSPECTION = (
    REPOSITORY_ROOT
    / "datasets/manifests/classification/mendeley_source_inspection.v1.json"
)


def _add_validation_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--registry", type=Path, default=DEFAULT_REGISTRY)
    parser.add_argument("--data-root", type=Path, default=DEFAULT_DATA_ROOT)
    parser.add_argument(
        "--extraction-policy", type=Path, default=DEFAULT_EXTRACTION_POLICY
    )
    parser.add_argument("--near-duplicate-threshold", type=int, default=4)
    parser.add_argument("--json", action="store_true")


def _run_validation(args: argparse.Namespace):
    extraction_policy = load_extraction_policy(args.extraction_policy)
    return validate_dataset(
        manifest_path=args.manifest,
        source_registry_path=args.registry,
        data_root=args.data_root,
        known_extraction_versions={extraction_policy["extraction_version"]},
        near_duplicate_threshold=args.near_duplicate_threshold,
    )


def _validate_command(args: argparse.Namespace) -> int:
    result = _run_validation(args)
    if args.json:
        print(json.dumps(result.as_json(), indent=2, sort_keys=True))
    else:
        for issue in result.issues:
            suffix = f" [{', '.join(issue.item_ids)}]" if issue.item_ids else ""
            print(f"[{issue.severity}] {issue.code}: {issue.message}{suffix}")
        print(
            f"items={len(result.rows)} errors={result.error_count} "
            f"warnings={result.warning_count} "
            f"training_eligible={str(result.training_eligible).lower()}"
        )
    return 1 if result.error_count else 0


def _report_command(args: argparse.Namespace) -> int:
    validation = _run_validation(args)
    report = build_report(validation)
    if args.json:
        print(json.dumps(report.as_json(), indent=2, sort_keys=True))
    else:
        print(format_report(report))
    return 1 if validation.error_count else 0


def _split_command(args: argparse.Namespace) -> int:
    rows = load_manifest(args.input_manifest)
    if not rows:
        raise DatasetConfigurationError("Cannot split an empty manifest")
    policy = load_split_policy(args.policy)
    output = assign_group_splits(rows, policy)
    if args.output_manifest.exists() and not args.overwrite:
        raise DatasetConfigurationError(
            f"Output manifest already exists: {args.output_manifest}; "
            "pass --overwrite after reviewing the target"
        )
    write_manifest(args.output_manifest, output)
    counts: dict[str, set[str]] = {}
    for row in output:
        counts.setdefault(row["split"], set()).add(row[policy["group_field"]])
    print(
        "Assigned source groups: "
        + ", ".join(f"{split}={len(groups)}" for split, groups in sorted(counts.items()))
    )
    return 0


def _extract_command(args: argparse.Namespace) -> int:
    registry = load_source_registry(args.registry)
    source = registry.get("dota-official")
    if source is None:
        raise DatasetConfigurationError("Source registry has no dota-official entry")
    extraction_policy = load_extraction_policy(args.extraction_policy)
    category_policy = load_category_policy(args.category_policy)
    normal_windows = load_normal_windows(args.normal_windows)
    visible_windows = load_visible_windows(args.visible_windows)
    if args.output_manifest.exists() and not args.overwrite:
        raise DatasetConfigurationError(
            f"Output manifest already exists: {args.output_manifest}; "
            "pass --overwrite after reviewing the target"
        )
    result = extract_dota_frames(
        annotation_root=args.annotation_root,
        source_root=args.source_root,
        output_root=args.output_root,
        normal_windows=normal_windows,
        visible_windows=visible_windows,
        category_policy=category_policy,
        extraction_policy=extraction_policy,
        source_registry_entry=source,
    )
    write_manifest(args.output_manifest, result.rows)
    for warning in result.warnings:
        print(f"[WARNING] {warning}")
    print(f"Extracted {len(result.rows)} byte-preserving still images")
    return 0


def _inspect_dota_command(args: argparse.Namespace) -> int:
    inspection = inspect_dota_metadata(args.metadata_root, args.frames_root)
    if args.json:
        print(json.dumps(inspection.as_json(), indent=2, sort_keys=True))
    else:
        print(f"Official repository commit: {inspection.official_commit}")
        print(f"Annotations: {inspection.annotation_count}")
        print(f"Ignored annotations: {inspection.ignored_annotation_count}")
        print(f"Metadata train clips: {inspection.metadata_train_count}")
        print(f"Metadata validation clips: {inspection.metadata_validation_count}")
        print(f"Unique source videos: {inspection.unique_source_video_count}")
        print(
            "Official split overlapping source videos: "
            f"{inspection.official_split_overlap_source_videos}"
        )
        print(f"Active source URL entries: {inspection.active_url_count}")
        if inspection.frame_event_directories_found is not None:
            print(
                "Frame event directories: "
                f"found={inspection.frame_event_directories_found} "
                f"missing={inspection.frame_event_directories_missing}"
            )
        for warning in inspection.warnings:
            print(f"[WARNING] {warning}")
        for error in inspection.errors:
            print(f"[ERROR] {error}")
    return 1 if inspection.errors else 0


def _inspect_mendeley_command(args: argparse.Namespace) -> int:
    result = inspect_mendeley_sources(
        accident_archive=args.accident_archive,
        dats_archive=args.dats_archive,
        dats_inventory_root=args.dats_inventory,
        accident_review_output=args.accident_review_output,
        dats_review_output=args.dats_review_output,
        report_output=args.report_output,
    )
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


def _create_review_batch_command(args: argparse.Namespace) -> int:
    excluded_items: set[str] = set()
    excluded_hashes: set[str] = set()
    excluded_groups: set[str] = set()
    if args.exclude_batch:
        inventory_rows = load_review_inventory(args.review_inventory)
        inventory_by_item = {row["source_item"]: row for row in inventory_rows}
        for excluded_batch in args.exclude_batch:
            with excluded_batch.open("r", encoding="utf-8-sig", newline="") as handle:
                reader = csv.DictReader(handle)
                if tuple(reader.fieldnames or ()) != (
                    "source_item",
                    "sha256",
                    "review_file",
                    "review_decision",
                    "label_basis",
                    "reviewer",
                    "review_date",
                    "rationale",
                ):
                    raise SourceInspectionError(
                        f"Review batch header is invalid: {excluded_batch}"
                    )
                for row in reader:
                    source_item = (row.get("source_item") or "").strip()
                    digest = (row.get("sha256") or "").strip()
                    excluded_items.add(source_item)
                    excluded_hashes.add(digest)
                    inventory_row = inventory_by_item.get(source_item)
                    if inventory_row is not None:
                        excluded_groups.add(inventory_row["source_group_id"])
    result = create_review_batch(
        archive_path=args.archive,
        review_inventory_path=args.review_inventory,
        output_root=args.output_root,
        source_dataset_id=args.source_dataset_id,
        start=args.start,
        limit=args.limit,
        excluded_source_items=excluded_items,
        excluded_hashes=excluded_hashes,
        excluded_source_groups=excluded_groups,
    )
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


def _apply_review_batch_command(args: argparse.Namespace) -> int:
    result = apply_review_batch(
        args.review_inventory,
        args.batch,
        propagate_exact_duplicates=args.propagate_exact_duplicates,
    )
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


def _apply_review_batches_command(args: argparse.Namespace) -> int:
    result = apply_review_batches_atomically(
        review_inventory_path=args.review_inventory,
        batch_paths=args.batch,
        ineligible_review_path=args.ineligible_review,
        propagate_exact_duplicates=args.propagate_exact_duplicates,
    )
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


def _validate_reviews_command(args: argparse.Namespace) -> int:
    result = validate_review_inventory(args.review_inventory)
    print(json.dumps(result, indent=2, sort_keys=True))
    return 1 if result["validation_errors"] else 0


def _validate_review_batch_command(args: argparse.Namespace) -> int:
    result = validate_review_batch(
        archive_path=args.archive,
        review_inventory_path=args.review_inventory,
        batch_path=args.batch,
        output_root=args.output_root,
    )
    print(json.dumps(result, indent=2, sort_keys=True))
    return 1 if result["validation_errors"] else 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="IRIS classification dataset preparation tools"
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    validate_parser = subparsers.add_parser("validate")
    _add_validation_arguments(validate_parser)
    validate_parser.set_defaults(handler=_validate_command)

    report_parser = subparsers.add_parser("report")
    _add_validation_arguments(report_parser)
    report_parser.set_defaults(handler=_report_command)

    split_parser = subparsers.add_parser("split")
    split_parser.add_argument("--input-manifest", type=Path, required=True)
    split_parser.add_argument("--output-manifest", type=Path, required=True)
    split_parser.add_argument("--policy", type=Path, default=DEFAULT_SPLIT_POLICY)
    split_parser.add_argument("--overwrite", action="store_true")
    split_parser.set_defaults(handler=_split_command)

    extract_parser = subparsers.add_parser("extract-dota")
    extract_parser.add_argument("--annotation-root", type=Path, required=True)
    extract_parser.add_argument("--source-root", type=Path, required=True)
    extract_parser.add_argument("--output-root", type=Path, default=DEFAULT_DATA_ROOT)
    extract_parser.add_argument("--output-manifest", type=Path, required=True)
    extract_parser.add_argument("--registry", type=Path, default=DEFAULT_REGISTRY)
    extract_parser.add_argument(
        "--normal-windows", type=Path, default=DEFAULT_NORMAL_WINDOWS
    )
    extract_parser.add_argument(
        "--visible-windows", type=Path, default=DEFAULT_VISIBLE_WINDOWS
    )
    extract_parser.add_argument(
        "--category-policy", type=Path, default=DEFAULT_CATEGORY_POLICY
    )
    extract_parser.add_argument(
        "--extraction-policy", type=Path, default=DEFAULT_EXTRACTION_POLICY
    )
    extract_parser.add_argument("--overwrite", action="store_true")
    extract_parser.set_defaults(handler=_extract_command)

    inspect_parser = subparsers.add_parser("inspect-dota")
    inspect_parser.add_argument("--metadata-root", type=Path, required=True)
    inspect_parser.add_argument("--frames-root", type=Path)
    inspect_parser.add_argument("--json", action="store_true")
    inspect_parser.set_defaults(handler=_inspect_dota_command)

    mendeley_parser = subparsers.add_parser("inspect-mendeley")
    mendeley_parser.add_argument(
        "--accident-archive", type=Path, default=DEFAULT_ACCIDENT_ARCHIVE
    )
    mendeley_parser.add_argument(
        "--dats-archive", type=Path, default=DEFAULT_DATS_ARCHIVE
    )
    mendeley_parser.add_argument(
        "--dats-inventory", type=Path, default=DEFAULT_DATS_INVENTORY
    )
    mendeley_parser.add_argument(
        "--accident-review-output", type=Path, default=DEFAULT_ACCIDENT_REVIEW
    )
    mendeley_parser.add_argument(
        "--dats-review-output", type=Path, default=DEFAULT_DATS_REVIEW
    )
    mendeley_parser.add_argument(
        "--report-output", type=Path, default=DEFAULT_MENDELEY_INSPECTION
    )
    mendeley_parser.set_defaults(handler=_inspect_mendeley_command)

    review_batch_parser = subparsers.add_parser("create-review-batch")
    review_batch_parser.add_argument(
        "--archive", type=Path, default=DEFAULT_DATS_ARCHIVE
    )
    review_batch_parser.add_argument(
        "--review-inventory", type=Path, default=DEFAULT_DATS_REVIEW
    )
    review_batch_parser.add_argument(
        "--source-dataset-id", default="dats-2022-mendeley"
    )
    review_batch_parser.add_argument("--output-root", type=Path, required=True)
    review_batch_parser.add_argument("--start", type=int, default=0)
    review_batch_parser.add_argument("--limit", type=int, default=100)
    review_batch_parser.add_argument(
        "--exclude-batch",
        type=Path,
        action="append",
        default=[],
        help="Previously generated batch whose items, hashes, and groups must be excluded.",
    )
    review_batch_parser.set_defaults(handler=_create_review_batch_command)

    apply_review_parser = subparsers.add_parser("apply-review-batch")
    apply_review_parser.add_argument(
        "--review-inventory", type=Path, default=DEFAULT_DATS_REVIEW
    )
    apply_review_parser.add_argument("--batch", type=Path, required=True)
    apply_review_parser.add_argument(
        "--propagate-exact-duplicates",
        action="store_true",
        help=(
            "Explicitly propagate an entered decision only to pending rows with "
            "the same SHA-256, source dataset, and conservative source group."
        ),
    )
    apply_review_parser.set_defaults(handler=_apply_review_batch_command)

    apply_review_batches_parser = subparsers.add_parser("apply-review-batches-atomic")
    apply_review_batches_parser.add_argument(
        "--review-inventory", type=Path, default=DEFAULT_ACCIDENT_REVIEW
    )
    apply_review_batches_parser.add_argument(
        "--batch", type=Path, action="append", required=True
    )
    apply_review_batches_parser.add_argument("--ineligible-review", type=Path, required=True)
    apply_review_batches_parser.add_argument(
        "--propagate-exact-duplicates", action="store_true"
    )
    apply_review_batches_parser.set_defaults(handler=_apply_review_batches_command)

    validate_review_parser = subparsers.add_parser("validate-reviews")
    validate_review_parser.add_argument(
        "--review-inventory", type=Path, default=DEFAULT_DATS_REVIEW
    )
    validate_review_parser.set_defaults(handler=_validate_reviews_command)

    validate_batch_parser = subparsers.add_parser("validate-review-batch")
    validate_batch_parser.add_argument("--archive", type=Path, required=True)
    validate_batch_parser.add_argument("--review-inventory", type=Path, required=True)
    validate_batch_parser.add_argument("--batch", type=Path, required=True)
    validate_batch_parser.add_argument("--output-root", type=Path, required=True)
    validate_batch_parser.set_defaults(handler=_validate_review_batch_command)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return args.handler(args)
    except (
        DatasetConfigurationError,
        ImageDependencyError,
        SourceInspectionError,
    ) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
