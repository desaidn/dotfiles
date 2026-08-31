from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import cast

from .checkouts import checked_out_path, require_clean
from .domain import Failure, Success
from .errors import DevflowError
from .git import Repository
from .review import ReviewRecord, decode_review_record, review_id_for
from .transitions import LandFacts, decide_land, decide_land_request

OID = re.compile(r"[0-9a-f]{40}|[0-9a-f]{64}")


@dataclass(frozen=True, slots=True)
class LandingResult:
    feature: str
    mainline_ref: str
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


def _candidate_tree(repository: Repository, main_oid: str, head_oid: str) -> str:
    result = repository.git("merge-tree", "--write-tree", main_oid, head_oid, check=False)
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


def _require_review_checkout(
    repository: Repository,
    checkout: Path,
    expected_branch: str,
    expected_head_oid: str,
) -> None:
    if checkout.is_symlink() or not checkout.is_dir():
        raise DevflowError("review_checkout_stale", "The reviewed checkout no longer exists as a regular directory.")
    checkout_repository = Repository.discover(checkout)
    if checkout_repository.common_dir != repository.common_dir:
        raise DevflowError("review_checkout_stale", "The stored review checkout belongs to a different repository.")
    symbolic_head = checkout_repository.git("symbolic-ref", "--quiet", "HEAD", check=False)
    if symbolic_head.returncode != 0 or symbolic_head.stdout.strip() != expected_branch:
        raise DevflowError("review_checkout_stale", "The reviewed checkout is no longer on its WIP branch.")
    if checkout_repository.ref_oid("HEAD") != expected_head_oid:
        raise DevflowError("review_checkout_stale", "The reviewed checkout is no longer at the approved revision.")
    require_clean(checkout_repository.cwd)


def land(repository: Repository, feature: str, target: str, approved_id: str, title: str) -> LandingResult:
    match decide_land_request(feature, target, title):
        case Failure(code, message):
            raise DevflowError(code, message)
        case Success(request):
            pass
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

    review_checkout = Path(stored.checkout)
    _require_review_checkout(repository, review_checkout, plan.wip_ref, plan.reviewed_head_oid)

    main_name = request.target
    main_ref = f"refs/heads/{main_name}"
    main_oid = repository.ref_oid(main_ref)
    if main_oid is None:
        raise DevflowError("mainline_not_found", f"Landing target {main_name} does not exist.")
    ancestry = repository.git("merge-base", "--is-ancestor", stored.change_set.base_oid, main_oid, check=False)
    if ancestry.returncode != 0:
        raise DevflowError("mainline_history_changed", "Current mainline no longer descends from the reviewed base.")
    main_checkout = checked_out_path(repository, main_ref)
    if main_checkout is not None:
        raise DevflowError(
            "mainline_checkout_conflict",
            (
                f"Devflow will not advance {main_name} while it is checked out at "
                f"{main_checkout}; explicitly switch or detach that checkout first."
            ),
        )

    tree_oid = _candidate_tree(repository, main_oid, plan.reviewed_head_oid)
    main_tree_oid = repository.git("rev-parse", f"{main_oid}^{{tree}}").stdout.strip()
    if tree_oid == main_tree_oid:
        raise DevflowError("landing_already_applied", "The approved change set is already present on mainline.")
    commit_oid = _commit(repository, tree_oid, main_oid, plan.title)
    _require_review_checkout(repository, review_checkout, plan.wip_ref, plan.reviewed_head_oid)
    updated = repository.update_refs_atomically(
        verifications=((plan.wip_ref, plan.reviewed_head_oid), (plan.review_ref, plan.reviewed_head_oid)),
        updates=((main_ref, commit_oid, main_oid),),
    )
    if updated.returncode != 0:
        if (
            repository.ref_oid(plan.wip_ref) != plan.reviewed_head_oid
            or repository.ref_oid(plan.review_ref) != plan.reviewed_head_oid
        ):
            raise DevflowError("approval_stale", "WIP or review state changed during landing.")
        if repository.ref_oid(main_ref) != main_oid:
            raise DevflowError("ref_update_rejected", "The landing target changed concurrently during landing.")
        raise DevflowError(
            "ref_update_rejected",
            updated.stderr.strip() or updated.stdout.strip() or "The atomic landing transaction was rejected.",
        )
    return LandingResult(name, main_ref, main_oid, commit_oid, tree_oid, approved_id)
