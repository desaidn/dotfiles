from __future__ import annotations

import os
import subprocess
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path

from .errors import DevflowError


@dataclass(frozen=True, slots=True)
class CommandResult:
    stdout: str
    stderr: str
    returncode: int


@dataclass(frozen=True, slots=True)
class Repository:
    cwd: Path

    @classmethod
    def discover(cls, cwd: Path | None = None) -> Repository:
        candidate = (cwd or Path.cwd()).resolve()
        result = command(("git", "rev-parse", "--show-toplevel"), cwd=candidate)
        if result.returncode != 0:
            raise DevflowError("not_a_git_repository", "Run devflow from inside a Git working tree.")
        return cls(Path(result.stdout.strip()).resolve())

    def git(
        self,
        *args: str,
        check: bool = True,
        env: Mapping[str, str] | None = None,
        stdin: str | None = None,
    ) -> CommandResult:
        result = command(("git", *args), cwd=self.cwd, env=env, stdin=stdin)
        if check and result.returncode != 0:
            detail = result.stderr.strip() or result.stdout.strip() or "Git command failed."
            raise DevflowError("git_command_failed", detail)
        return result

    @property
    def common_dir(self) -> Path:
        value = self.git("rev-parse", "--path-format=absolute", "--git-common-dir").stdout.strip()
        return Path(value).resolve()

    @property
    def zero_oid(self) -> str:
        object_format = self.git("rev-parse", "--show-object-format").stdout.strip()
        match object_format:
            case "sha1":
                return "0" * 40
            case "sha256":
                return "0" * 64
            case _:
                raise DevflowError("object_format_unsupported", f"Unsupported Git object format: {object_format}")

    def ref_oid(self, ref: str) -> str | None:
        result = self.git("rev-parse", "--verify", f"{ref}^{{commit}}", check=False)
        return result.stdout.strip() if result.returncode == 0 else None

    def update_ref(self, ref: str, new_oid: str, old_oid: str) -> None:
        result = self.git("update-ref", ref, new_oid, old_oid, check=False)
        if result.returncode != 0:
            detail = result.stderr.strip() or "The ref changed concurrently."
            raise DevflowError("ref_update_rejected", detail)

    def delete_ref(self, ref: str, old_oid: str) -> None:
        result = self.git("update-ref", "-d", ref, old_oid, check=False)
        if result.returncode != 0:
            detail = result.stderr.strip() or "The ref changed concurrently."
            raise DevflowError("ref_update_rejected", detail)


def command(
    argv: Sequence[str],
    *,
    cwd: Path,
    env: Mapping[str, str] | None = None,
    stdin: str | None = None,
) -> CommandResult:
    process_env = os.environ.copy()
    process_env.update(env or {})
    try:
        completed = subprocess.run(
            argv,
            cwd=cwd,
            env=process_env,
            input=stdin,
            text=True,
            capture_output=True,
            check=False,
        )
    except FileNotFoundError as error:
        raise DevflowError("command_not_found", f"Required command not found: {argv[0]}") from error
    return CommandResult(completed.stdout, completed.stderr, completed.returncode)
