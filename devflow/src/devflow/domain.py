from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Literal, cast

type ChangeSetKind = Literal["wip", "external"]
type JsonScalar = None | bool | int | float | str
type JsonValue = JsonScalar | list[JsonValue] | dict[str, JsonValue]
type JsonObject = dict[str, JsonValue]


@dataclass(frozen=True, slots=True)
class Failure:
    code: str
    message: str


@dataclass(frozen=True, slots=True)
class Success[T]:
    value: T


type Outcome[T] = Success[T] | Failure


def decode_json_value(value: object) -> Outcome[JsonValue]:
    if value is None or isinstance(value, (bool, str)):
        return Success(value)
    if type(value) is int:
        return Success(value)
    if isinstance(value, float):
        if math.isfinite(value):
            return Success(value)
        return Failure("json_value_invalid", "JSON numbers must be finite.")
    if isinstance(value, list):
        items: list[JsonValue] = []
        for item in cast(list[object], value):
            match decode_json_value(item):
                case Success(decoded):
                    items.append(decoded)
                case Failure(code, message):
                    return Failure(code, message)
        return Success(items)
    if isinstance(value, dict):
        result: JsonObject = {}
        for key, item in cast(dict[object, object], value).items():
            if not isinstance(key, str):
                return Failure("json_value_invalid", "JSON object keys must be strings.")
            match decode_json_value(item):
                case Success(decoded):
                    result[key] = decoded
                case Failure(code, message):
                    return Failure(code, message)
        return Success(result)
    return Failure("json_value_invalid", "Value is not representable as JSON.")
