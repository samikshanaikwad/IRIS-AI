from __future__ import annotations

import hashlib
import io
from dataclasses import dataclass
from pathlib import Path


class ImageDependencyError(RuntimeError):
    """Raised when the pinned local image decoder is unavailable."""


class ImageDecodeError(ValueError):
    """Raised when a dataset item cannot be decoded as a supported image."""


@dataclass(frozen=True)
class ImageProbe:
    width: int
    height: int
    image_format: str
    perceptual_hash: str


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def probe_image(path: Path) -> ImageProbe:
    with path.open("rb") as handle:
        return probe_image_bytes(handle.read())


def probe_image_bytes(data: bytes) -> ImageProbe:
    """Fully decode image bytes and calculate the canonical 64-bit dHash."""

    try:
        from PIL import Image, UnidentifiedImageError
    except ImportError as error:
        raise ImageDependencyError(
            "Pillow is required for full image decoding; install the pinned "
            "ml/classification/requirements-dataset.txt environment"
        ) from error

    try:
        with Image.open(io.BytesIO(data)) as image:
            image_format = (image.format or "").upper()
            width, height = image.size
            image.verify()
        if image_format not in {"JPEG", "PNG"}:
            raise ImageDecodeError(f"Unsupported decoded image format: {image_format}")
        with Image.open(io.BytesIO(data)) as image:
            image.load()
            grayscale = image.convert("L").resize((9, 8), Image.Resampling.LANCZOS)
            pixels = list(grayscale.getdata())
    except (OSError, UnidentifiedImageError) as error:
        raise ImageDecodeError(str(error)) from error

    bits = 0
    for row in range(8):
        row_offset = row * 9
        for column in range(8):
            bits = (bits << 1) | int(
                pixels[row_offset + column] > pixels[row_offset + column + 1]
            )
    return ImageProbe(
        width=width,
        height=height,
        image_format=image_format,
        perceptual_hash=f"{bits:016x}",
    )


def hamming_distance(left: str, right: str) -> int:
    return (int(left, 16) ^ int(right, 16)).bit_count()
