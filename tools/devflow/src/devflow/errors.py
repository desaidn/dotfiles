from __future__ import annotations

from typing import final, override


@final
class DevflowError(Exception):
    __slots__: tuple[str, str] = ("code", "message")

    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code: str = code
        self.message: str = message

    @override
    def __str__(self) -> str:
        return self.message
