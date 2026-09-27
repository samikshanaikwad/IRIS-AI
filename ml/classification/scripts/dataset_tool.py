from __future__ import annotations

import sys
from pathlib import Path

CLASSIFICATION_ROOT = Path(__file__).resolve().parents[1]
if str(CLASSIFICATION_ROOT) not in sys.path:
    sys.path.insert(0, str(CLASSIFICATION_ROOT))

from iris_dataset.cli import main  # noqa: E402


if __name__ == "__main__":
    raise SystemExit(main())
