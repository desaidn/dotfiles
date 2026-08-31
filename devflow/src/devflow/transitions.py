from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Literal

from .domain import ChangeSetKind, Failure, Outcome, Success

FEATURE = re.compile(r"[a-zA-Z0-9][a-zA-Z0-9._-]*")
type MainlineName = Literal["main", "mainline", "master"]
MAINLINE_NAMES: tuple[MainlineName, ...] = ("main", "mainline", "master")


def decide_feature_name(value: str) -> Outcome[str]:
    if FEATURE.fullmatch(value) is None:
        return Failure(
            "invalid_feature_name",
            "Feature names must contain only letters, numbers, dots, underscores, and hyphens.",
        )
    return Success(value)


@dataclass(frozen=True, slots=True)
class StartFacts:
    main_oid: str
    current_branch: str | None
    existing_oid: str | None


@dataclass(frozen=True, slots=True)
class StartPlan:
    branch: str
    start_oid: str | None
    created: bool
    switch_required: bool


def decide_start(feature: str, facts: StartFacts) -> Outcome[StartPlan]:
    if isinstance(outcome := decide_feature_name(feature), Failure):
        return outcome
    branch = f"wip/{feature}"
    if facts.existing_oid is None:
        return Success(StartPlan(branch, facts.main_oid, True, True))
    return Success(StartPlan(branch, None, False, facts.current_branch != branch))


@dataclass(frozen=True, slots=True)
class ReviewRequest:
    source: str | None
    base: str | None
    name: str | None


@dataclass(frozen=True, slots=True)
class LocalReview:
    name: str


@dataclass(frozen=True, slots=True)
class ExternalReview:
    source: str
    base: str
    name: str


type ReviewIntent = LocalReview | ExternalReview


def decide_review(current_branch: str | None, request: ReviewRequest) -> Outcome[ReviewIntent]:
    match request:
        case ReviewRequest(None, None, None):
            if current_branch is None or not current_branch.startswith("wip/"):
                return Failure(
                    "wip_source_required",
                    "Run an implicit review from its WIP branch or supply --source, --base, and --name.",
                )
            return Success(LocalReview(current_branch.removeprefix("wip/")))
        case ReviewRequest(str(source), str(base), str(name)):
            return Success(ExternalReview(source, base, name))
        case ReviewRequest():
            return Failure(
                "external_change_set_incomplete",
                "External reviews require explicit --source, --base, and --name values.",
            )


@dataclass(frozen=True, slots=True)
class LandRequest:
    feature: str
    target: MainlineName
    title: str


def decide_land_request(feature: str, target: str, title: str) -> Outcome[LandRequest]:
    if isinstance(outcome := decide_feature_name(feature), Failure):
        return outcome
    match target:
        case "main" | "mainline" | "master":
            mainline = target
        case _:
            return Failure("invalid_landing_target", "Landing target must be main, mainline, or master.")
    if not title.strip() or "\n" in title or "\r" in title:
        return Failure("invalid_landing_title", "Landing title must be one non-empty line.")
    return Success(LandRequest(feature, mainline, title))


@dataclass(frozen=True, slots=True)
class LandFacts:
    review_name: str
    change_kind: ChangeSetKind
    change_source: str
    reviewed_head_oid: str
    reviewed_tree_oid: str
    wip_oid: str | None
    review_oid: str | None
    actual_tree_oid: str


@dataclass(frozen=True, slots=True)
class LandPlan:
    feature: str
    wip_ref: str
    review_ref: str
    reviewed_head_oid: str
    title: str


def decide_land(request: LandRequest, facts: LandFacts) -> Outcome[LandPlan]:
    expected_source = f"wip/{request.feature}"
    if facts.review_name != request.feature or facts.change_kind != "wip" or facts.change_source != expected_source:
        return Failure("approval_mismatch", "Approval does not belong to this complete WIP feature.")
    if facts.wip_oid != facts.reviewed_head_oid or facts.review_oid != facts.reviewed_head_oid:
        return Failure("approval_stale", "WIP or review state changed after this approval snapshot.")
    if facts.actual_tree_oid != facts.reviewed_tree_oid:
        return Failure("review_record_invalid", "Stored review tree does not match the reviewed WIP revision.")
    return Success(
        LandPlan(
            request.feature,
            f"refs/heads/wip/{request.feature}",
            f"refs/heads/review/{request.feature}",
            facts.reviewed_head_oid,
            request.title,
        )
    )
