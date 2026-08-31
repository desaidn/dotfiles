from __future__ import annotations

import json
import os
import subprocess
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path

from .domain import JsonObject
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
    def hooks_dir(self) -> Path:
        configured = self.git("config", "--path", "--get", "core.hooksPath", check=False)
        if configured.returncode == 0 and configured.stdout.strip():
            path = Path(configured.stdout.strip())
            if not path.is_absolute():
                raise DevflowError(
                    "relative_hooks_path_unsupported",
                    "core.hooksPath must be absolute so one guard applies consistently across all worktrees.",
                )
        else:
            value = self.git("rev-parse", "--path-format=absolute", "--git-path", "hooks").stdout.strip()
            path = Path(value)
        resolved = path.resolve()
        try:
            _ = resolved.relative_to(self.common_dir)
        except ValueError as error:
            raise DevflowError(
                "hooks_path_outside_repository",
                "core.hooksPath must stay inside this repository's common Git directory.",
            ) from error
        return resolved

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

    def update_ref(self, ref: str, new_oid: str, old_oid: str, *, authorize: bool = False) -> None:
        update = authorized_update(ref, old_oid, new_oid)
        env = authorization_env(update) if authorize else None
        result = self.git("update-ref", ref, new_oid, old_oid, check=False, env=env)
        if result.returncode != 0:
            detail = result.stderr.strip() or "The ref changed concurrently."
            raise DevflowError("ref_update_rejected", detail)

    def update_refs_atomically(
        self,
        *,
        verifications: Sequence[tuple[str, str]],
        updates: Sequence[tuple[str, str, str]],
    ) -> CommandResult:
        zero_oid = self.zero_oid
        instructions = ["start"]
        instructions.extend(f"verify {ref} {old_oid}" for ref, old_oid in verifications)
        instructions.extend(f"update {ref} {new_oid} {old_oid}" for ref, new_oid, old_oid in updates)
        instructions.extend(("prepare", "commit"))
        authorizations = tuple(
            [authorized_update(ref, old_oid, zero_oid) for ref, old_oid in verifications]
            + [authorized_update(ref, old_oid, new_oid) for ref, new_oid, old_oid in updates]
        )
        return self.git(
            "update-ref",
            "--stdin",
            check=False,
            env=authorization_env(*authorizations),
            stdin="\n".join(instructions) + "\n",
        )

    def mainline(self) -> tuple[str, str]:
        for name in ("main", "mainline", "master"):
            ref = f"refs/heads/{name}"
            if oid := self.ref_oid(ref):
                return name, oid
        raise DevflowError("mainline_not_found", "Expected a local main, mainline, or master branch.")


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


def authorized_update(ref: str, old_oid: str, new_oid: str) -> JsonObject:
    return {"ref": ref, "old": old_oid, "new": new_oid}


def authorization_env(*updates: JsonObject) -> dict[str, str]:
    return {"DEVFLOW_REF_UPDATES": json.dumps(list(updates), separators=(",", ":"), sort_keys=True)}
