from __future__ import annotations

import argparse
import json
import sys
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import final, override

from .checkouts import StartResult, start
from .domain import Failure, JsonObject, Outcome, Success
from .errors import DevflowError
from .git import Repository
from .harness import Harness, HarnessAction, HarnessResult, apply_harness
from .landing import LandingResult, land
from .review import ReviewResult, change_set_json, review
from .state import workflow_lock


@final
class RawArguments(argparse.Namespace):
    as_json: bool
    command: str | None
    feature: str | None
    base: str | None
    name: str | None
    target: str | None
    approved: str | None
    title: str | None
    harness_action: str | None
    harness_name: str | None

    @override
    def __init__(self) -> None:
        super().__init__()
        self.as_json = False
        self.command = None
        self.feature = None
        self.base = None
        self.name = None
        self.target = None
        self.approved = None
        self.title = None
        self.harness_action = None
        self.harness_name = None


@dataclass(frozen=True, slots=True)
class StartCommand:
    feature: str


@dataclass(frozen=True, slots=True)
class ReviewCommand:
    base: str
    name: str | None


@dataclass(frozen=True, slots=True)
class LandCommand:
    feature: str
    target: str
    approved: str
    title: str


@dataclass(frozen=True, slots=True)
class HarnessCommand:
    action: HarnessAction
    harness: Harness


type CliCommand = StartCommand | ReviewCommand | LandCommand | HarnessCommand


@dataclass(frozen=True, slots=True)
class Invocation:
    as_json: bool
    command: CliCommand


@dataclass(frozen=True, slots=True)
class StartedResult:
    result: StartResult


type ExecutionResult = StartedResult | ReviewResult | LandingResult | HarnessResult


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="devflow")
    _ = parser.add_argument("--json", action="store_true", dest="as_json")
    commands = parser.add_subparsers(dest="command", required=True)

    start_command = commands.add_parser("start")
    _ = start_command.add_argument("feature")
    review_command = commands.add_parser("review")
    _ = review_command.add_argument("--base", required=True)
    _ = review_command.add_argument("--name")
    land_command = commands.add_parser("land")
    _ = land_command.add_argument("feature")
    _ = land_command.add_argument("--target", required=True)
    _ = land_command.add_argument("--approved", required=True)
    _ = land_command.add_argument("--title", required=True)
    harness = commands.add_parser("harness")
    harness_commands = harness.add_subparsers(dest="harness_action", required=True)
    for action in ("install", "remove", "status"):
        harness_action = harness_commands.add_parser(action)
        _ = harness_action.add_argument("harness_name", choices=("codex", "claude"))
    return parser


def _parse_arguments(argv: Sequence[str] | None) -> RawArguments:
    raw = RawArguments()
    _ = _parser().parse_args(argv, namespace=raw)
    return raw


def _argument_failure() -> Failure:
    return Failure("unsupported_command", "Unsupported command arguments.")


def _decode_arguments(raw: RawArguments) -> Outcome[Invocation]:
    match raw.command:
        case "start" if raw.feature is not None:
            return Success(Invocation(raw.as_json, StartCommand(raw.feature)))
        case "review" if raw.base is not None:
            return Success(Invocation(raw.as_json, ReviewCommand(raw.base, raw.name)))
        case "land" if (
            raw.feature is not None
            and raw.target is not None
            and raw.approved is not None
            and raw.title is not None
        ):
            return Success(Invocation(raw.as_json, LandCommand(raw.feature, raw.target, raw.approved, raw.title)))
        case "harness":
            match raw.harness_action, raw.harness_name:
                case (("install" | "remove" | "status" as action), ("codex" | "claude" as harness)):
                    return Success(Invocation(raw.as_json, HarnessCommand(action, harness)))
                case _:
                    return _argument_failure()
        case _:
            return _argument_failure()


def _execute(command: CliCommand) -> ExecutionResult:
    if isinstance(command, HarnessCommand):
        return apply_harness(command.action, command.harness)
    repository = Repository.discover(Path.cwd())
    match command:
        case StartCommand(feature):
            with workflow_lock(repository.common_dir):
                return StartedResult(start(repository, feature))
        case ReviewCommand(base, name):
            with workflow_lock(repository.common_dir):
                return review(repository, base=base, name=name)
        case LandCommand(feature, target, approved, title):
            with workflow_lock(repository.common_dir):
                return land(repository, feature, target, approved, title)


def _result_json(result: ExecutionResult) -> JsonObject:
    match result:
        case StartedResult(StartResult(branch, cwd, created)):
            return {
                "branch": branch,
                "cwd": str(cwd),
                "created": created,
            }
        case ReviewResult(review_id, name, review_ref, change_set, checkout, tab_id, pane_id, session_id):
            return {
                "review_id": review_id,
                "review_ref": review_ref,
                "name": name,
                "checkout": str(checkout),
                "tab_id": tab_id,
                "pane_id": pane_id,
                "session_id": session_id,
                "change_set": change_set_json(change_set),
            }
        case LandingResult(feature, target_ref, previous_oid, commit_oid, tree_oid, review_id):
            return {
                "feature": feature,
                "target_ref": target_ref,
                "previous_oid": previous_oid,
                "commit_oid": commit_oid,
                "tree_oid": tree_oid,
                "review_id": review_id,
            }
        case HarnessResult(harness, target, status, changed):
            return {
                "harness": harness,
                "target": str(target),
                "status": status,
                "changed": changed,
            }


def _plain_result(result: ExecutionResult) -> str:
    match result:
        case StartedResult(StartResult(cwd=cwd)):
            return str(cwd)
        case ReviewResult(review_id=review_id):
            return review_id
        case LandingResult(commit_oid=commit_oid):
            return commit_oid
        case HarnessResult(status=status):
            return status


def _emit(result: ExecutionResult, as_json: bool) -> None:
    if as_json:
        envelope: JsonObject = {"ok": True}
        envelope.update(_result_json(result))
        print(json.dumps(envelope, separators=(",", ":"), sort_keys=True))
    else:
        print(_plain_result(result))


def _emit_error(error: DevflowError, as_json: bool) -> None:
    if as_json:
        payload: JsonObject = {
            "ok": False,
            "error": {"code": error.code, "message": error.message},
        }
        print(json.dumps(payload, separators=(",", ":"), sort_keys=True))
    else:
        print(f"devflow: {error.message}", file=sys.stderr)


def main(argv: Sequence[str] | None = None) -> int:
    raw = _parse_arguments(argv)
    try:
        match _decode_arguments(raw):
            case Success(invocation):
                _emit(_execute(invocation.command), invocation.as_json)
            case Failure(code, message):
                raise DevflowError(code, message)
    except DevflowError as error:
        _emit_error(error, raw.as_json)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
