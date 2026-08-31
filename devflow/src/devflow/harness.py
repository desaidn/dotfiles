from __future__ import annotations

import os
import stat
import tempfile
from dataclasses import dataclass
from importlib import resources
from pathlib import Path
from typing import Literal

from .domain import Failure, Outcome, Success
from .errors import DevflowError

type Harness = Literal["codex", "claude"]
type HarnessAction = Literal["install", "remove", "status"]
type HarnessStatus = Literal["absent", "installed", "outdated"]
BEGIN = b"<!-- dotfiles-devflow:begin v1 -->"
END = b"<!-- dotfiles-devflow:end v1 -->"
TOKEN = b"dotfiles-devflow:"


@dataclass(frozen=True, slots=True)
class HarnessResult:
    harness: Harness
    target: Path
    status: HarnessStatus
    changed: bool


@dataclass(frozen=True, slots=True)
class HarnessBlock:
    status: HarnessStatus
    prefix: bytes
    suffix: bytes


def _home() -> Path:
    value = os.environ.get("HOME", "")
    if not value:
        raise DevflowError("home_required", "HOME must be set to install agent guidance.")
    return _safe_root(value, "HOME")


def _safe_root(value: str, label: str) -> Path:
    selected = Path(value)
    if not selected.is_absolute():
        raise DevflowError("harness_root_unsafe", f"{label} must be an absolute non-root path.")
    normalized = Path(os.path.normpath(selected))
    if normalized == Path(normalized.anchor):
        raise DevflowError("harness_root_unsafe", f"{label} must be an absolute non-root path.")
    return normalized


def target_for(harness: Harness) -> Path:
    match harness:
        case "codex":
            root = os.environ.get("CODEX_HOME")
            return (_safe_root(root, "CODEX_HOME") if root is not None else _home() / ".codex") / "AGENTS.md"
        case "claude":
            return _home() / ".claude" / "CLAUDE.md"


def _owned_block() -> bytes:
    body = resources.files("devflow").joinpath("guidance.md").read_bytes()
    if not body.endswith(b"\n"):
        body += b"\n"
    return b"\n" + BEGIN + b"\n" + body + END + b"\n"


def _read_target(target: Path) -> tuple[bytes, int]:
    if os.path.lexists(target.parent) and (target.parent.is_symlink() or not target.parent.is_dir()):
        raise DevflowError("harness_target_unsafe", f"Harness parent must be a regular directory: {target.parent}")
    if not os.path.lexists(target):
        return b"", 0o644
    details = target.lstat()
    if stat.S_ISLNK(details.st_mode) or not stat.S_ISREG(details.st_mode):
        raise DevflowError("harness_target_unsafe", f"Harness target must be a regular non-symlink file: {target}")
    return target.read_bytes(), stat.S_IMODE(details.st_mode)


def _malformed() -> Failure:
    return Failure(
        "harness_block_malformed",
        "The devflow guidance markers are duplicated, incomplete, unknown, or damaged; refusing to modify the file.",
    )


def _decode_block(data: bytes, current_block: bytes) -> Outcome[HarnessBlock]:
    if TOKEN not in data:
        return Success(HarnessBlock("absent", data, b""))
    if data.count(BEGIN) != 1 or data.count(END) != 1 or data.count(TOKEN) != 2:
        return _malformed()

    begin_start = data.find(BEGIN)
    begin_end = begin_start + len(BEGIN)
    end_start = data.find(END)
    end_end = end_start + len(END)
    owned_start = begin_start - 1
    owned_end = end_end + 1
    framing_is_canonical = (
        begin_start > 0
        and begin_end < end_start
        and owned_end <= len(data)
        and data[owned_start:begin_start] == b"\n"
        and data[begin_end : begin_end + 1] == b"\n"
        and data[end_start - 1 : end_start] == b"\n"
        and data[end_end:owned_end] == b"\n"
    )
    if not framing_is_canonical:
        return _malformed()
    owned = data[owned_start:owned_end]
    status: HarnessStatus = "installed" if owned == current_block else "outdated"
    return Success(HarnessBlock(status, data[:owned_start], data[owned_end:]))


def _atomic_replace(target: Path, data: bytes, mode: int) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.parent.is_symlink() or not target.parent.is_dir():
        raise DevflowError("harness_target_unsafe", f"Harness parent must be a regular directory: {target.parent}")
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{target.name}.", suffix=".tmp", dir=target.parent)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            _ = stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        temporary.chmod(mode)
        os.replace(temporary, target)
    finally:
        temporary.unlink(missing_ok=True)


def apply_harness(action: HarnessAction, harness: Harness) -> HarnessResult:
    target = target_for(harness)
    data, mode = _read_target(target)
    block = _owned_block()
    match _decode_block(data, block):
        case Failure(code, message):
            raise DevflowError(code, message)
        case Success(owned):
            pass
    match action, owned.status:
        case "status", _:
            return HarnessResult(harness, target, owned.status, False)
        case "install", "installed":
            return HarnessResult(harness, target, "installed", False)
        case "install", "absent":
            _atomic_replace(target, data + block, mode)
            return HarnessResult(harness, target, "installed", True)
        case "install", "outdated":
            _atomic_replace(target, owned.prefix + block + owned.suffix, mode)
            return HarnessResult(harness, target, "installed", True)
        case "remove", "absent":
            return HarnessResult(harness, target, "absent", False)
        case "remove", "installed" | "outdated":
            _atomic_replace(target, owned.prefix + owned.suffix, mode)
            return HarnessResult(harness, target, "absent", True)
