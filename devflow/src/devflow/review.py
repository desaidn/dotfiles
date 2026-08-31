from __future__ import annotations

import hashlib
import json
import math
import os
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Never, cast

from .checkouts import checked_out_path, require_clean, validate_feature
from .domain import ChangeSetKind, Failure, JsonObject, JsonValue, Outcome, Success, decode_json_value
from .errors import DevflowError
from .git import Repository, command
from .state import atomic_write_json, prepare_json_destination
from .transitions import ExternalReview, LocalReview, ReviewRequest, decide_review


@dataclass(frozen=True, slots=True)
class ChangeSet:
    base_oid: str
    head_oid: str
    source: str
    tree_oid: str
    kind: ChangeSetKind


@dataclass(frozen=True, slots=True)
class ReviewResult:
    review_id: str
    name: str
    review_ref: str
    change_set: ChangeSet
    checkout: Path
    tab_id: str
    pane_id: str
    session_id: str


@dataclass(frozen=True, slots=True)
class ReviewRecord:
    version: int
    review_id: str
    name: str
    review_ref: str
    change_set: ChangeSet
    checkout: str
    tab_id: str
    pane_id: str
    session_id: str


@dataclass(frozen=True, slots=True)
class HunkSession:
    session_id: str
    cwd: str
    repo_root: str
    source_label: str
    input_kind: str
    title: str


@dataclass(frozen=True, slots=True)
class PollSettings:
    timeout: float
    interval: float


def change_set_json(change_set: ChangeSet) -> JsonObject:
    return {
        "base_oid": change_set.base_oid,
        "head_oid": change_set.head_oid,
        "source": change_set.source,
        "tree_oid": change_set.tree_oid,
        "kind": change_set.kind,
    }


def review_record_json(record: ReviewRecord) -> JsonObject:
    return {
        "version": record.version,
        "review_id": record.review_id,
        "name": record.name,
        "review_ref": record.review_ref,
        **change_set_json(record.change_set),
        "checkout": record.checkout,
        "tab_id": record.tab_id,
        "pane_id": record.pane_id,
        "session_id": record.session_id,
    }


def decode_review_record(decoded: object) -> Outcome[ReviewRecord]:
    if not isinstance(decoded, dict):
        return Failure("review_record_invalid", "Stored review must be a JSON object.")
    raw = cast(dict[object, object], decoded)
    if not all(isinstance(key, str) for key in raw):
        return Failure("review_record_invalid", "Stored review must have string keys.")
    value = cast(dict[str, object], raw)
    expected = {
        "version",
        "review_id",
        "name",
        "review_ref",
        "base_oid",
        "head_oid",
        "source",
        "tree_oid",
        "kind",
        "checkout",
        "tab_id",
        "pane_id",
        "session_id",
    }
    if set(value) != expected:
        return Failure("review_record_invalid", "Stored review has unexpected fields.")
    version = value["version"]
    if type(version) is not int or version != 1:
        return Failure("review_record_invalid", "Stored review has an unsupported version.")
    string_keys = expected - {"version"}
    strings: dict[str, str] = {}
    for key in string_keys:
        selected = value[key]
        if not isinstance(selected, str) or not selected:
            return Failure("review_record_invalid", "Stored review has invalid field types.")
        strings[key] = selected
    kind_value = strings["kind"]
    if kind_value not in ("wip", "external"):
        return Failure("review_record_invalid", "Stored review has an invalid change-set kind.")
    change_set = ChangeSet(
        strings["base_oid"],
        strings["head_oid"],
        strings["source"],
        strings["tree_oid"],
        kind_value,
    )
    return Success(
        ReviewRecord(
            version,
            strings["review_id"],
            strings["name"],
            strings["review_ref"],
            change_set,
            strings["checkout"],
            strings["tab_id"],
            strings["pane_id"],
            strings["session_id"],
        )
    )


def _resolve_commit(repository: Repository, value: str, label: str) -> str:
    oid = repository.ref_oid(value)
    if oid is None:
        raise DevflowError("revision_not_found", f"Cannot resolve {label}: {value}")
    return oid


def _current_branch(repository: Repository) -> str | None:
    result = repository.git("symbolic-ref", "--quiet", "--short", "HEAD", check=False)
    return result.stdout.strip() if result.returncode == 0 and result.stdout.strip() else None


def build_change_set(
    repository: Repository,
    *,
    source: str | None,
    base: str | None,
    name: str | None,
) -> tuple[str, ChangeSet]:
    decision = decide_review(_current_branch(repository), ReviewRequest(source, base, name))
    match decision:
        case Failure(code, message):
            raise DevflowError(code, message)
        case Success(intent):
            match intent:
                case LocalReview(wip_name):
                    _ = validate_feature(wip_name)
                    selected_source = f"wip/{wip_name}"
                    require_clean(repository.cwd)
                    head_oid = _resolve_commit(repository, "HEAD", "source")
                    main_name, main_oid = repository.mainline()
                    ancestry = repository.git("merge-base", "--is-ancestor", main_oid, head_oid, check=False)
                    if ancestry.returncode != 0:
                        raise DevflowError(
                            "wip_requires_main_merge",
                            f"Merge current {main_name} into {selected_source} before review.",
                        )
                    tree_oid = repository.git("rev-parse", f"{head_oid}^{{tree}}").stdout.strip()
                    return wip_name, ChangeSet(main_oid, head_oid, selected_source, tree_oid, "wip")
                case ExternalReview(selected_source, selected_base, selected_name):
                    review_name = validate_feature(selected_name)
                    base_oid = _resolve_commit(repository, selected_base, "base")
                    head_oid = _resolve_commit(repository, selected_source, "source")
                    ancestry = repository.git("merge-base", "--is-ancestor", base_oid, head_oid, check=False)
                    if ancestry.returncode != 0:
                        raise DevflowError(
                            "external_base_not_ancestor",
                            (
                                "External review base must be an ancestor of head so "
                                "BASE...HEAD preserves the recorded change set."
                            ),
                        )
                    if _resolve_commit(repository, "HEAD", "checkout HEAD") != head_oid:
                        raise DevflowError(
                            "review_source_checkout_mismatch",
                            "The invoking checkout must already be at the external review source revision.",
                        )
                    require_clean(repository.cwd)
                    tree_oid = repository.git("rev-parse", f"{head_oid}^{{tree}}").stdout.strip()
                    return review_name, ChangeSet(base_oid, head_oid, selected_source, tree_oid, "external")


def review_id_for(name: str, change_set: ChangeSet) -> str:
    identity = json.dumps(
        {"name": name, **change_set_json(change_set)},
        separators=(",", ":"),
        sort_keys=True,
    ).encode()
    return hashlib.sha256(identity).hexdigest()[:24]


def _json_result(result_stdout: str, code: str) -> dict[str, JsonValue]:
    try:
        value = cast(object, json.loads(result_stdout))
    except json.JSONDecodeError as error:
        raise DevflowError(code, "Tool returned invalid JSON.") from error
    match decode_json_value(value):
        case Success(decoded) if isinstance(decoded, dict):
            return decoded
        case Success() | Failure():
            raise DevflowError(code, "Tool returned an unexpected JSON value.")


def _nested_string(value: dict[str, JsonValue], *path: str) -> str:
    current: JsonValue = value
    for part in path:
        if not isinstance(current, dict) or part not in current:
            return ""
        current = current[part]
    return current if isinstance(current, str) else ""


def _hunk_sessions(checkout: Path) -> tuple[HunkSession, ...]:
    result = command(("hunk", "session", "list", "--json"), cwd=checkout)
    if result.returncode != 0:
        raise DevflowError(
            "hunk_session_query_failed",
            result.stderr.strip() or result.stdout.strip() or "Hunk session query failed.",
        )
    payload = _json_result(result.stdout, "hunk_invalid_response")
    raw_sessions = payload.get("sessions")
    if not isinstance(raw_sessions, list):
        raise DevflowError("hunk_invalid_response", "Hunk did not return a session list.")
    sessions: list[HunkSession] = []
    for raw_session in raw_sessions:
        if not isinstance(raw_session, dict):
            raise DevflowError("hunk_invalid_response", "Hunk returned a malformed session record.")
        fields = {
            key: value
            for key in ("sessionId", "cwd", "repoRoot", "sourceLabel", "inputKind", "title")
            if isinstance((value := raw_session.get(key)), str) and value
        }
        if len(fields) != 6:
            raise DevflowError("hunk_invalid_response", "Hunk returned a malformed session record.")
        sessions.append(
            HunkSession(
                fields["sessionId"],
                fields["cwd"],
                fields["repoRoot"],
                fields["sourceLabel"],
                fields["inputKind"],
                fields["title"],
            )
        )
    return tuple(sessions)


def _same_checkout(value: str, checkout: Path) -> bool:
    path = Path(value)
    if not path.is_absolute():
        return False
    try:
        return os.path.samefile(path, checkout)
    except OSError:
        return False


def _sessions_for_checkout(checkout: Path) -> tuple[HunkSession, ...]:
    matches: list[HunkSession] = []
    for session in _hunk_sessions(checkout):
        path_matches = tuple(
            _same_checkout(value, checkout) for value in (session.cwd, session.repo_root, session.source_label)
        )
        if all(path_matches):
            matches.append(session)
        elif any(path_matches):
            raise DevflowError(
                "hunk_session_mismatch",
                "Hunk session paths do not consistently identify the requested checkout.",
            )
    return tuple(matches)


def _exact_review_session(checkout: Path, change_set: ChangeSet) -> str | None:
    sessions = _sessions_for_checkout(checkout)
    if len(sessions) > 1:
        raise DevflowError("hunk_session_ambiguous", "Multiple Hunk sessions match the review checkout.")
    if not sessions:
        return None
    session = sessions[0]
    identity = f"{checkout.resolve().name} {change_set.base_oid}...{change_set.head_oid}"
    if session.input_kind != "vcs" or session.title != identity:
        raise DevflowError(
            "hunk_session_mismatch",
            "Hunk session does not show the exact immutable review aggregate.",
        )
    return session.session_id


def _close_tab(checkout: Path, tab_id: str) -> DevflowError | None:
    try:
        result = command(("herdr", "tab", "close", tab_id), cwd=checkout)
    except DevflowError as error:
        return error
    if result.returncode != 0:
        return DevflowError(
            "herdr_tab_close_failed",
            result.stderr.strip() or result.stdout.strip() or f"Herdr could not close tab {tab_id}.",
        )
    return None


def _raise_after_tab_cleanup(checkout: Path, tab_id: str, original: DevflowError) -> Never:
    cleanup = _close_tab(checkout, tab_id)
    if cleanup is not None:
        raise DevflowError(
            original.code,
            f"{original.message} Review-tab cleanup also failed: {cleanup.message}",
        ) from original
    raise original


def _poll_settings() -> PollSettings:
    try:
        timeout = float(os.environ.get("DEVFLOW_HUNK_TIMEOUT", "10"))
        interval = float(os.environ.get("DEVFLOW_HUNK_POLL_INTERVAL", "0.1"))
    except ValueError as error:
        raise DevflowError("hunk_poll_settings_invalid", "Hunk polling settings must be numeric.") from error
    if not math.isfinite(timeout) or not math.isfinite(interval) or timeout < 0 or interval <= 0:
        raise DevflowError(
            "hunk_poll_settings_invalid",
            "Hunk timeout must be finite and nonnegative; polling interval must be finite and positive.",
        )
    return PollSettings(timeout, interval)


def _review_workspace() -> str:
    if os.environ.get("HERDR_ENV") != "1":
        raise DevflowError("herdr_required", "Review must be started from a Herdr-managed pane.")
    workspace = os.environ.get("HERDR_WORKSPACE_ID", "")
    if not workspace:
        raise DevflowError("herdr_workspace_required", "HERDR_WORKSPACE_ID is required for review.")
    return workspace


def _ensure_no_hunk_session(checkout: Path) -> None:
    if _sessions_for_checkout(checkout):
        raise DevflowError("hunk_session_exists", f"A Hunk session already exists for {checkout}.")


def _launch_review(
    checkout: Path,
    name: str,
    change_set: ChangeSet,
    workspace: str,
    poll_settings: PollSettings,
) -> tuple[str, str, str]:
    review_env = {
        "DEVFLOW_REVIEW_BASE_OID": change_set.base_oid,
        "DEVFLOW_REVIEW_HEAD_OID": change_set.head_oid,
    }
    created = command(
        (
            "herdr",
            "tab",
            "create",
            "--workspace",
            workspace,
            "--cwd",
            str(checkout),
            "--label",
            f"review/{name}",
            "--env",
            f"DEVFLOW_REVIEW_BASE_OID={change_set.base_oid}",
            "--env",
            f"DEVFLOW_REVIEW_HEAD_OID={change_set.head_oid}",
            "--focus",
        ),
        cwd=checkout,
    )
    if created.returncode != 0:
        raise DevflowError(
            "herdr_tab_create_failed", created.stderr.strip() or "Herdr could not create the review tab."
        )
    envelope = _json_result(created.stdout, "herdr_invalid_response")
    tab_id = _nested_string(envelope, "result", "tab", "tab_id")
    pane_id = _nested_string(envelope, "result", "root_pane", "pane_id")
    if _nested_string(envelope, "result", "type") != "tab_created" or not tab_id or not pane_id:
        if tab_id:
            _raise_after_tab_cleanup(
                checkout,
                tab_id,
                DevflowError("herdr_invalid_response", "Herdr did not return the created tab and pane IDs."),
            )
        raise DevflowError("herdr_invalid_response", "Herdr did not return the created tab and pane IDs.")

    try:
        started = command(("herdr", "pane", "run", pane_id, "nvim", "+HunkReview"), cwd=checkout, env=review_env)
        if started.returncode != 0:
            raise DevflowError("herdr_pane_run_failed", started.stderr.strip() or "Herdr could not start Neovim.")
        if started.stdout or started.stderr:
            raise DevflowError("herdr_invalid_response", "Herdr returned unexpected output after starting Neovim.")
        deadline = time.monotonic() + poll_settings.timeout
        while time.monotonic() <= deadline:
            if session := _exact_review_session(checkout, change_set):
                return tab_id, pane_id, session
            time.sleep(poll_settings.interval)
        raise DevflowError("hunk_session_timeout", "Timed out waiting for Hunk to register the review session.")
    except DevflowError as error:
        _raise_after_tab_cleanup(checkout, tab_id, error)


def review(
    repository: Repository,
    *,
    source: str | None,
    base: str | None,
    name: str | None,
) -> ReviewResult:
    review_name, change_set = build_change_set(repository, source=source, base=base, name=name)
    poll_settings = _poll_settings()
    workspace = _review_workspace()
    review_ref = f"refs/heads/review/{review_name}"
    review_id = review_id_for(review_name, change_set)
    record_path = repository.common_dir / "devflow" / "reviews" / f"{review_id}.json"
    prepare_json_destination(record_path)
    old_oid = repository.ref_oid(review_ref) or repository.zero_oid
    if old_oid != change_set.head_oid and (user_checkout := checked_out_path(repository, review_ref)) is not None:
        raise DevflowError(
            "review_checkout_conflict",
            (
                f"Cannot advance review/{review_name} while it is checked out at {user_checkout}; "
                "explicitly switch or detach that checkout first."
            ),
        )
    checkout = repository.cwd
    _ensure_no_hunk_session(checkout)
    if old_oid != change_set.head_oid:
        repository.update_ref(review_ref, change_set.head_oid, old_oid)
    tab_id, pane_id, session_id = _launch_review(checkout, review_name, change_set, workspace, poll_settings)
    result = ReviewResult(review_id, review_name, review_ref, change_set, checkout, tab_id, pane_id, session_id)
    record = ReviewRecord(1, review_id, review_name, review_ref, change_set, str(checkout), tab_id, pane_id, session_id)
    try:
        atomic_write_json(record_path, review_record_json(record))
    except DevflowError as error:
        _raise_after_tab_cleanup(checkout, tab_id, error)
    except OSError as error:
        _raise_after_tab_cleanup(
            checkout,
            tab_id,
            DevflowError("review_record_write_failed", f"Could not persist review {review_id}: {error}"),
        )
    return result
