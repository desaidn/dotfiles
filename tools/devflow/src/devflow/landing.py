from __future__ import annotations

import json
import re
from dataclasses import dataclass
from typing import cast

from .checkouts import require_clean
from .domain import Failure, Success
from .errors import DevflowError
from .git import Repository
from .review import ReviewRecord, decode_review_record, review_id_for
from .transitions import LandFacts, decide_land, decide_land_request

OID = re.compile(r"[0-9a-f]{40}|[0-9a-f]{64}")


@dataclass(frozen=True, slots=True)
class LandingResult:
    feature: str
    target_ref: str
    previous_oid: str
    commit_oid: str
    tree_oid: str
    review_id: str


def load_review(repository: Repository, approved_id: str) -> ReviewRecord:
    if not re.fullmatch(r"[0-9a-f]{24}", approved_id):
        raise DevflowError("approval_not_found", "The approved review ID is invalid or unknown.")
    path = repository.common_dir / "devflow" / "reviews" / f"{approved_id}.json"
    if path.is_symlink() or not path.is_file():
        raise DevflowError("approval_not_found", f"No stored review matches approval {approved_id}.")
    try:
        decoded = cast(object, json.loads(path.read_text()))
    except (OSError, json.JSONDecodeError) as error:
        raise DevflowError("review_record_invalid", f"Cannot read stored review {approved_id}.") from error
    match decode_review_record(decoded):
        case Success(stored):
            pass
        case Failure(code, message):
            raise DevflowError(code, message)
    if stored.review_id != approved_id or review_id_for(stored.name, stored.change_set) != approved_id:
        raise DevflowError("review_record_invalid", "Stored review identity does not match its immutable change set.")
    return stored


def _candidate_tree(repository: Repository, target_oid: str, head_oid: str) -> str:
    result = repository.git("merge-tree", "--write-tree", target_oid, head_oid, check=False)
    if result.returncode != 0:
        raise DevflowError(
            "landing_conflict", result.stdout.strip() or result.stderr.strip() or "Landing has conflicts."
        )
    first_line = result.stdout.splitlines()[0] if result.stdout.splitlines() else ""
    if OID.fullmatch(first_line) is None:
        raise DevflowError("landing_candidate_invalid", "Git did not return a landing candidate tree.")
    return first_line


def _commit(repository: Repository, tree_oid: str, parent_oid: str, title: str) -> str:
    result = repository.git("commit-tree", tree_oid, "-p", parent_oid, stdin=f"{title}\n", check=False)
    oid = result.stdout.strip()
    if result.returncode != 0 or OID.fullmatch(oid) is None:
        raise DevflowError("landing_commit_failed", result.stderr.strip() or "Git could not create the squash commit.")
    return oid


def _current_branch(repository: Repository) -> str | None:
    result = repository.git("symbolic-ref", "--quiet", "--short", "HEAD", check=False)
    return result.stdout.strip() if result.returncode == 0 and result.stdout.strip() else None


def _require_target_checkout(repository: Repository, target: str, expected_oid: str | None = None) -> str:
    if _current_branch(repository) != target:
        raise DevflowError(
            "landing_target_checkout_required",
            f"Run land from the clean checkout already on {target}.",
        )
    require_clean(repository.cwd)
    head_oid = repository.ref_oid("HEAD")
    if head_oid is None or (expected_oid is not None and head_oid != expected_oid):
        raise DevflowError("landing_target_changed", f"Landing target {target} changed during landing.")
    return head_oid


def land(repository: Repository, feature: str, target: str, approved_id: str, title: str) -> LandingResult:
    match decide_land_request(feature, target, title):
        case Failure(code, message):
            raise DevflowError(code, message)
        case Success(request):
            pass
    target_ref = f"refs/heads/{request.target}"
    valid_target = repository.git("check-ref-format", target_ref, check=False)
    if valid_target.returncode != 0:
        raise DevflowError("invalid_landing_target", f"Invalid local landing target: {request.target}")
    target_oid = repository.ref_oid(target_ref)
    if target_oid is None:
        raise DevflowError("landing_target_not_found", f"Landing target {request.target} does not exist.")
    _ = _require_target_checkout(repository, request.target, target_oid)

    name = request.feature
    stored = load_review(repository, approved_id)
    wip_ref = f"refs/heads/wip/{name}"
    review_ref = f"refs/heads/review/{name}"
    wip_oid = repository.ref_oid(wip_ref)
    review_oid = repository.ref_oid(review_ref)
    actual_tree = repository.git("rev-parse", f"{stored.change_set.head_oid}^{{tree}}").stdout.strip()
    match decide_land(
        request,
        LandFacts(
            stored.name,
            stored.change_set.kind,
            stored.change_set.source,
            stored.change_set.head_oid,
            stored.change_set.tree_oid,
            wip_oid,
            review_oid,
            actual_tree,
        ),
    ):
        case Failure(code, message):
            raise DevflowError(code, message)
        case Success(plan):
            pass

    ancestry = repository.git("merge-base", "--is-ancestor", stored.change_set.base_oid, target_oid, check=False)
    if ancestry.returncode != 0:
        raise DevflowError(
            "landing_target_missing_base",
            "Landing target must contain the reviewed base.",
        )

    tree_oid = _candidate_tree(repository, target_oid, plan.reviewed_head_oid)
    target_tree_oid = repository.git("rev-parse", f"{target_oid}^{{tree}}").stdout.strip()
    if tree_oid == target_tree_oid:
        raise DevflowError("landing_already_applied", "The approved change set is already present on target.")
    commit_oid = _commit(repository, tree_oid, target_oid, plan.title)

    _ = _require_target_checkout(repository, request.target, target_oid)
    if (
        repository.ref_oid(plan.wip_ref) != plan.reviewed_head_oid
        or repository.ref_oid(plan.review_ref) != plan.reviewed_head_oid
    ):
        raise DevflowError("approval_stale", "WIP or review state changed during landing.")
    merged = repository.git(
        "merge",
        "--ff-only",
        "--no-overwrite-ignore",
        "--no-edit",
        "--no-stat",
        commit_oid,
        check=False,
    )
    if merged.returncode != 0:
        raise DevflowError(
            "landing_checkout_conflict",
            merged.stderr.strip() or merged.stdout.strip() or "Git could not apply the landing commit.",
        )
    if repository.ref_oid(target_ref) != commit_oid or repository.ref_oid("HEAD") != commit_oid:
        raise DevflowError("landing_target_changed", f"Landing target {request.target} changed during landing.")
    require_clean(repository.cwd)
    return LandingResult(name, target_ref, target_oid, commit_oid, tree_oid, approved_id)
