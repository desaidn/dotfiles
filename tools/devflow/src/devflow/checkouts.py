from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from .domain import Failure, Success
from .errors import DevflowError
from .git import Repository
from .transitions import StartFacts, decide_feature_name, decide_start


@dataclass(frozen=True, slots=True)
class WorktreeRecord:
    path: Path
    branch: str | None
    head: str


@dataclass(frozen=True, slots=True)
class StartResult:
    branch: str
    cwd: Path
    created: bool


def validate_feature(value: str) -> str:
    match decide_feature_name(value):
        case Success(selected):
            return selected
        case Failure(code, message):
            raise DevflowError(code, message)


def worktree_records(repository: Repository) -> tuple[WorktreeRecord, ...]:
    output = repository.git("worktree", "list", "--porcelain", "-z").stdout
    records: list[WorktreeRecord] = []
    current: dict[str, str] = {}
    for field in output.split("\0"):
        if field == "":
            if "worktree" in current and "HEAD" in current:
                records.append(
                    WorktreeRecord(
                        Path(current["worktree"]).resolve(),
                        current.get("branch"),
                        current["HEAD"],
                    )
                )
            current = {}
            continue
        key, _, value = field.partition(" ")
        current[key] = value
    return tuple(records)


def checked_out_path(repository: Repository, branch_ref: str) -> Path | None:
    return next((record.path for record in worktree_records(repository) if record.branch == branch_ref), None)


def require_clean(path: Path) -> None:
    result = Repository(path).git("status", "--porcelain", "--untracked-files=normal")
    if result.stdout:
        raise DevflowError("dirty_checkout", f"Checkout has uncommitted changes: {path}")


def _switch_without_overwriting_ignored(repository: Repository, *args: str) -> None:
    result = repository.git("switch", "--no-overwrite-ignore", *args, check=False)
    if result.returncode != 0:
        raise DevflowError(
            "checkout_conflict",
            result.stderr.strip() or "Checkout would overwrite ignored user state.",
        )


def start(repository: Repository, feature: str) -> StartResult:
    head_oid = repository.ref_oid("HEAD")
    if head_oid is None:
        raise DevflowError("head_required", "Start requires a checkout with at least one commit.")
    branch = f"wip/{feature}"
    existing_oid = repository.ref_oid(f"refs/heads/{branch}")
    current_branch = repository.git("branch", "--show-current").stdout.strip() or None
    match decide_start(feature, StartFacts(head_oid, current_branch, existing_oid)):
        case Failure(code, message):
            raise DevflowError(code, message)
        case Success(plan):
            pass
    require_clean(repository.cwd)
    if plan.created:
        if plan.start_oid is None:
            raise DevflowError("workflow_plan_invalid", "A new WIP plan requires a starting revision.")
        _switch_without_overwriting_ignored(repository, "-c", plan.branch, plan.start_oid)
    elif plan.switch_required:
        _switch_without_overwriting_ignored(repository, plan.branch)
    return StartResult(plan.branch, repository.cwd, plan.created)
