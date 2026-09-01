from __future__ import annotations

import re
from dataclasses import dataclass

from .domain import ChangeSetKind, Failure, Outcome, Success

FEATURE = re.compile(r"[a-zA-Z0-9][a-zA-Z0-9._-]*")


def decide_feature_name(value: str) -> Outcome[str]:
    if FEATURE.fullmatch(value) is None:
        return Failure(
            "invalid_feature_name",
            "Feature names must contain only letters, numbers, dots, underscores, and hyphens.",
        )
    return Success(value)


@dataclass(frozen=True, slots=True)
class StartFacts:
    head_oid: str
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
        return Success(StartPlan(branch, facts.head_oid, True, True))
    return Success(StartPlan(branch, None, False, facts.current_branch != branch))


@dataclass(frozen=True, slots=True)
class ReviewRequest:
    base: str
    name: str | None


@dataclass(frozen=True, slots=True)
class LocalReview:
    name: str
    base: str


@dataclass(frozen=True, slots=True)
class ExternalReview:
    base: str
    name: str


type ReviewIntent = LocalReview | ExternalReview


def decide_review(current_branch: str | None, request: ReviewRequest) -> Outcome[ReviewIntent]:
    if current_branch is not None and current_branch.startswith("wip/") and request.name is None:
        return Success(LocalReview(current_branch.removeprefix("wip/"), request.base))
    if request.name is None:
        return Failure("external_review_name_required", "External reviews require --name.")
    return Success(ExternalReview(request.base, request.name))


@dataclass(frozen=True, slots=True)
class LandRequest:
    feature: str
    target: str
    title: str


def decide_land_request(feature: str, target: str, title: str) -> Outcome[LandRequest]:
    if isinstance(outcome := decide_feature_name(feature), Failure):
        return outcome
    if target.startswith(("wip/", "review/")):
        return Failure("reserved_landing_target", "Landing target cannot be a WIP or review branch.")
    if not title.strip() or "\n" in title or "\r" in title:
        return Failure("invalid_landing_title", "Landing title must be one non-empty line.")
    return Success(LandRequest(feature, target, title))


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
