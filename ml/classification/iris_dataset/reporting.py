from __future__ import annotations

from collections import Counter
from dataclasses import asdict, dataclass
from statistics import mean, median
from typing import Any

from .validation import ValidationResult


@dataclass(frozen=True)
class DatasetReport:
    total_items: int
    accident_items: int
    non_accident_items: int
    counts_by_split: dict[str, int]
    counts_by_source: dict[str, int]
    counts_by_source_category: dict[str, int]
    counts_by_license_status: dict[str, int]
    unique_source_groups: int
    images_per_group_minimum: int | None
    images_per_group_maximum: int | None
    images_per_group_mean: float | None
    images_per_group_median: float | None
    width_minimum: int | None
    width_maximum: int | None
    height_minimum: int | None
    height_maximum: int | None
    exact_duplicate_findings: int
    near_duplicate_findings: int
    missing_or_corrupt_findings: int
    validation_errors: int
    validation_warnings: int
    training_eligible: bool

    def as_json(self) -> dict[str, Any]:
        return asdict(self)


def build_report(validation: ValidationResult) -> DatasetReport:
    rows = validation.rows
    labels = Counter(row["label"] for row in rows)
    splits = Counter(row["split"] for row in rows)
    sources = Counter(row["source_dataset_id"] for row in rows)
    categories = Counter(row["source_category"] for row in rows)
    license_statuses = Counter(row["license_status"] for row in rows)
    groups = Counter(row["source_group_id"] for row in rows if row["source_group_id"])
    group_counts = list(groups.values())

    widths = [int(row["width"]) for row in rows if row["width"].isdigit()]
    heights = [int(row["height"]) for row in rows if row["height"].isdigit()]
    exact_codes = {"CROSS_SPLIT_EXACT_DUPLICATE", "EXACT_DUPLICATE_CONTENT"}
    near_codes = {"CROSS_SPLIT_NEAR_DUPLICATE", "NEAR_DUPLICATE_CANDIDATE"}
    damaged_codes = {
        "MISSING_FILE",
        "ZERO_BYTE_FILE",
        "IMAGE_DECODE_FAILURE",
        "UNSUPPORTED_IMAGE_EXTENSION",
    }

    return DatasetReport(
        total_items=len(rows),
        accident_items=labels["accident"],
        non_accident_items=labels["non_accident"],
        counts_by_split=dict(sorted(splits.items())),
        counts_by_source=dict(sorted(sources.items())),
        counts_by_source_category=dict(sorted(categories.items())),
        counts_by_license_status=dict(sorted(license_statuses.items())),
        unique_source_groups=len(groups),
        images_per_group_minimum=min(group_counts) if group_counts else None,
        images_per_group_maximum=max(group_counts) if group_counts else None,
        images_per_group_mean=mean(group_counts) if group_counts else None,
        images_per_group_median=median(group_counts) if group_counts else None,
        width_minimum=min(widths) if widths else None,
        width_maximum=max(widths) if widths else None,
        height_minimum=min(heights) if heights else None,
        height_maximum=max(heights) if heights else None,
        exact_duplicate_findings=sum(
            issue.code in exact_codes for issue in validation.issues
        ),
        near_duplicate_findings=sum(
            issue.code in near_codes for issue in validation.issues
        ),
        missing_or_corrupt_findings=sum(
            issue.code in damaged_codes for issue in validation.issues
        ),
        validation_errors=validation.error_count,
        validation_warnings=validation.warning_count,
        training_eligible=validation.training_eligible,
    )


def format_report(report: DatasetReport) -> str:
    eligibility = "YES" if report.training_eligible else "NO"
    lines = [
        "IRIS classification dataset report",
        f"Real items: {report.total_items}",
        f"Accident: {report.accident_items}",
        f"Non-accident: {report.non_accident_items}",
        f"Unique source groups: {report.unique_source_groups}",
        f"Counts by split: {report.counts_by_split}",
        f"Counts by source: {report.counts_by_source}",
        f"Counts by source category: {report.counts_by_source_category}",
        f"License statuses: {report.counts_by_license_status}",
        "Images per source group (min/max/mean/median): "
        f"{report.images_per_group_minimum}/"
        f"{report.images_per_group_maximum}/"
        f"{report.images_per_group_mean}/"
        f"{report.images_per_group_median}",
        "Image dimensions (width min-max, height min-max): "
        f"{report.width_minimum}-{report.width_maximum}, "
        f"{report.height_minimum}-{report.height_maximum}",
        f"Exact duplicate findings: {report.exact_duplicate_findings}",
        f"Near-duplicate findings: {report.near_duplicate_findings}",
        f"Missing/corrupt findings: {report.missing_or_corrupt_findings}",
        f"Validation errors: {report.validation_errors}",
        f"Validation warnings: {report.validation_warnings}",
        f"Training eligible: {eligibility}",
    ]
    if report.total_items == 0:
        lines.append("No real dataset has been acquired or derived.")
    return "\n".join(lines)
