from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
from collections.abc import Iterable
from pathlib import Path
from typing import cast

from .errors import DevflowError

HOOKS = {
    "reference-transaction": "devflow-reference-transaction",
    "pre-push": "devflow-pre-push",
}
MAINLINE_REFS = frozenset(
    {
        "refs/heads/main",
        "refs/heads/mainline",
        "refs/heads/master",
    }
)
OBJECT_ID = re.compile(r"(?:[0-9a-f]{40}|[0-9a-f]{64})")
WIP_HEAD = re.compile(r"ref:refs/heads/wip/[a-zA-Z0-9][a-zA-Z0-9._-]*")


def _hook_target(executable: str) -> Path:
    override = os.environ.get("DEVFLOW_HOOK_BIN_DIR")
    candidate = Path(override, executable) if override else Path(shutil.which(executable) or "")
    if not str(candidate) or not candidate.is_file() or not os.access(candidate, os.X_OK):
        raise DevflowError("hook_entrypoint_not_found", f"Cannot find executable hook entry point {executable!r}.")
    return candidate.resolve()


def install_hooks(hooks_dir: Path) -> None:
    hooks_dir.mkdir(parents=True, exist_ok=True)
    planned = tuple((hooks_dir / name, _hook_target(executable)) for name, executable in HOOKS.items())
    for link, target in planned:
        if os.path.lexists(link):
            if link.is_symlink() and link.resolve() == target:
                continue
            raise DevflowError("hook_conflict", f"Refusing to replace foreign Git hook: {link}")
    for link, target in planned:
        if not os.path.lexists(link):
            link.symlink_to(target)


def _is_zero(oid: str) -> bool:
    return oid != "" and set(oid) == {"0"}


def _authorized(ref: str, old_oid: str, new_oid: str) -> bool:
    raw = os.environ.get("DEVFLOW_REF_UPDATES", "")
    if not raw:
        return False
    try:
        parsed = cast(object, json.loads(raw))
    except json.JSONDecodeError:
        return False
    if not isinstance(parsed, list):
        return False
    for raw_item in cast(list[object], parsed):
        if not isinstance(raw_item, dict):
            continue
        item = cast(dict[str, object], raw_item)
        if item.get("ref") == ref and item.get("old") == old_oid and item.get("new") == new_oid:
            return True
    return False


def _is_ancestor(old_oid: str, new_oid: str) -> bool:
    return (
        subprocess.run(
            ("git", "merge-base", "--is-ancestor", old_oid, new_oid),
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        ).returncode
        == 0
    )


def _protected_ref_allowed(old_oid: str, new_oid: str, ref: str) -> bool:
    if _authorized(ref, old_oid, new_oid):
        return True
    if ref == "HEAD":
        return WIP_HEAD.fullmatch(new_oid) is not None or (
            not _is_zero(new_oid) and OBJECT_ID.fullmatch(new_oid) is not None
        )
    if ref.startswith("refs/heads/wip/"):
        if _is_zero(new_oid):
            return False
        return _is_zero(old_oid) or _is_ancestor(old_oid, new_oid)
    if ref.startswith("refs/heads/review/") or ref in MAINLINE_REFS:
        return False
    return not ref.startswith("refs/heads/")


def _deny(message: str) -> int:
    print(f"devflow: {message}", file=sys.stderr)
    return 1


def reference_transaction_main() -> int:
    state = sys.argv[1] if len(sys.argv) > 1 else ""
    if state != "prepared":
        return 0
    for line in sys.stdin:
        fields = line.rstrip("\n").split(" ", 2)
        if len(fields) != 3:
            return _deny("invalid reference-transaction input")
        old_oid, new_oid, ref = fields
        if not _protected_ref_allowed(old_oid, new_oid, ref):
            return _deny(f"protected ref update rejected: {ref}")
    return 0


def _push_lines(lines: Iterable[str]) -> bool:
    for line in lines:
        fields = line.rstrip("\n").split()
        if len(fields) != 4:
            return False
        local_ref, local_oid, remote_ref, remote_oid = fields
        if remote_ref.startswith("refs/heads/review/"):
            return False
        if remote_ref.startswith("refs/heads/wip/"):
            if _is_zero(local_oid):
                return False
            if not _is_zero(remote_oid) and not _is_ancestor(remote_oid, local_oid):
                return False
            continue
        if remote_ref in MAINLINE_REFS:
            if local_ref != remote_ref or _is_zero(local_oid) or _is_zero(remote_oid):
                return False
            local = subprocess.run(
                ("git", "rev-parse", "--verify", f"{remote_ref}^{{commit}}"),
                stdin=subprocess.DEVNULL,
                capture_output=True,
                text=True,
                check=False,
            )
            if local.returncode != 0 or local.stdout.strip() != local_oid:
                return False
            if not _is_ancestor(remote_oid, local_oid):
                return False
            continue
        if remote_ref.startswith("refs/heads/"):
            return False
    return True


def pre_push_main() -> int:
    if _push_lines(sys.stdin):
        return 0
    return _deny("push violates guarded WIP, review, or mainline policy")


if __name__ == "__main__":
    raise SystemExit(reference_transaction_main())
