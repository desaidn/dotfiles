from __future__ import annotations

import fcntl
import json
import os
import stat
import tempfile
from collections.abc import Generator
from contextlib import contextmanager
from pathlib import Path

from .domain import JsonObject
from .errors import DevflowError


def _ensure_state_directory(path: Path) -> None:
    if os.path.lexists(path):
        details = path.lstat()
        if stat.S_ISLNK(details.st_mode) or not stat.S_ISDIR(details.st_mode):
            raise DevflowError("workflow_state_unsafe", f"Workflow state directory must be regular: {path}")
        return
    _ensure_state_directory(path.parent)
    try:
        path.mkdir()
    except FileExistsError:
        _ensure_state_directory(path)


def prepare_json_destination(path: Path) -> None:
    _ensure_state_directory(path.parent)
    if os.path.lexists(path):
        details = path.lstat()
        if stat.S_ISLNK(details.st_mode) or not stat.S_ISREG(details.st_mode):
            raise DevflowError("workflow_state_unsafe", f"Workflow state file must be regular: {path}")


def atomic_write_json(path: Path, payload: JsonObject) -> None:
    prepare_json_destination(path)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w") as stream:
            _ = stream.write(json.dumps(payload, separators=(",", ":"), sort_keys=True) + "\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


@contextmanager
def workflow_lock(common_dir: Path) -> Generator[None]:
    path = common_dir / "devflow" / "workflow.lock"
    _ensure_state_directory(path.parent)
    if os.path.lexists(path):
        details = path.lstat()
        if stat.S_ISLNK(details.st_mode) or not stat.S_ISREG(details.st_mode):
            raise DevflowError("workflow_state_unsafe", f"Workflow lock must be a regular file: {path}")
    flags = os.O_CREAT | os.O_RDWR | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
    try:
        descriptor = os.open(path, flags, 0o600)
    except OSError as error:
        raise DevflowError("workflow_state_unsafe", f"Cannot open workflow lock: {path}") from error
    try:
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise DevflowError(
                "workflow_busy", "Another devflow mutation is already running in this repository."
            ) from error
        yield
    finally:
        fcntl.flock(descriptor, fcntl.LOCK_UN)
        os.close(descriptor)
