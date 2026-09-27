from __future__ import annotations

from dataclasses import dataclass, field
from typing import Iterable


@dataclass
class _Node:
    value: str
    index: int
    children: dict[int, "_Node"] = field(default_factory=dict)


class PerceptualHashIndex:
    """BK-tree for practical Hamming-radius searches over 64-bit dHashes."""

    def __init__(self) -> None:
        self._root: _Node | None = None

    @staticmethod
    def _distance(left: str, right: str) -> int:
        return (int(left, 16) ^ int(right, 16)).bit_count()

    def add(self, value: str, index: int) -> None:
        node = _Node(value=value, index=index)
        if self._root is None:
            self._root = node
            return
        current = self._root
        while True:
            distance = self._distance(value, current.value)
            child = current.children.get(distance)
            if child is None:
                current.children[distance] = node
                return
            current = child

    def query(self, value: str, maximum_distance: int) -> list[tuple[int, int]]:
        if self._root is None:
            return []
        matches: list[tuple[int, int]] = []
        pending = [self._root]
        while pending:
            node = pending.pop()
            distance = self._distance(value, node.value)
            if distance <= maximum_distance:
                matches.append((node.index, distance))
            lower = distance - maximum_distance
            upper = distance + maximum_distance
            pending.extend(
                child
                for edge, child in node.children.items()
                if lower <= edge <= upper
            )
        return matches


def find_near_duplicate_pairs(
    values: Iterable[tuple[int, str]], maximum_distance: int
) -> list[tuple[int, int, int]]:
    index = PerceptualHashIndex()
    pairs: list[tuple[int, int, int]] = []
    for item_index, value in values:
        for prior_index, distance in index.query(value, maximum_distance):
            pairs.append((prior_index, item_index, distance))
        index.add(value, item_index)
    return pairs
