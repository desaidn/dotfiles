from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path
from typing import Any

BIN_DIR = Path(sys.executable).parent
DEVFLOW = BIN_DIR / "devflow"


def run(
    argv: list[str],
    *,
    cwd: Path,
    env: dict[str, str] | None = None,
    stdin: str | None = None,
) -> subprocess.CompletedProcess[str]:
    process_env = os.environ.copy()
    process_env.update(env or {})
    return subprocess.run(
        argv,
        cwd=cwd,
        env=process_env,
        input=stdin,
        text=True,
        capture_output=True,
        check=False,
    )


def git(repo: Path, *args: str, env: dict[str, str] | None = None) -> str:
    result = run(["git", *args], cwd=repo, env=env)
    if result.returncode != 0:
        raise AssertionError(f"git {' '.join(args)} failed:\nstdout={result.stdout}\nstderr={result.stderr}")
    return result.stdout.strip()


def json_output(result: subprocess.CompletedProcess[str]) -> dict[str, Any]:
    return json.loads(result.stdout)


class RepoCase(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        git(self.repo, "init", "-b", "main")
        git(self.repo, "config", "user.name", "Devflow Test")
        git(self.repo, "config", "user.email", "devflow@example.test")
        (self.repo / "README.md").write_text("initial\n")
        git(self.repo, "add", "README.md")
        git(self.repo, "commit", "-m", "Initial")
        self.env = {
            "XDG_STATE_HOME": str(self.root / "state"),
        }

    def tearDown(self) -> None:
        self.temp.cleanup()

    def devflow(
        self, *args: str, cwd: Path | None = None, env: dict[str, str] | None = None
    ) -> subprocess.CompletedProcess[str]:
        command_env = self.env | (env or {})
        return run([str(DEVFLOW), *args], cwd=cwd or self.repo, env=command_env)

    def fake_review_tools(self) -> tuple[dict[str, str], Path]:
        fake_bin = self.root / "fake-bin"
        fake_bin.mkdir()
        log = self.root / "tools.jsonl"
        started = self.root / "review-started"

        herdr = fake_bin / "herdr"
        herdr.write_text(
            textwrap.dedent(
                f"""\
                #!{sys.executable}
                import json, os, pathlib, sys, time
                log = pathlib.Path(os.environ["FAKE_TOOL_LOG"])
                with log.open("a") as stream:
                    stream.write(json.dumps({{
                        "tool": "herdr", "argv": sys.argv[1:], "cwd": os.getcwd(),
                        "base": os.environ.get("DEVFLOW_REVIEW_BASE_OID"),
                        "head": os.environ.get("DEVFLOW_REVIEW_HEAD_OID"),
                    }}) + "\\n")
                if sys.argv[1:3] == ["tab", "create"]:
                    print(json.dumps({{
                        "result": {{
                            "type": "tab_created",
                            "tab": {{"tab_id": "w1:t9"}},
                            "root_pane": {{"pane_id": "w1:p9"}},
                        }}
                    }}))
                elif sys.argv[1:3] == ["pane", "run"]:
                    if os.environ.get("FAKE_PANE_FAIL") == "1":
                        print(json.dumps({{"error": "pane_failed"}}), file=sys.stderr)
                        sys.exit(1)
                    time.sleep(float(os.environ.get("FAKE_PANE_DELAY", "0")))
                    pathlib.Path(os.environ["FAKE_REVIEW_STARTED"]).write_text(json.dumps({{
                        "cwd": os.getcwd(),
                        "base": os.environ.get("DEVFLOW_REVIEW_BASE_OID"),
                        "head": os.environ.get("DEVFLOW_REVIEW_HEAD_OID"),
                    }}))
                    if state_path := os.environ.get("FAKE_REVIEW_STATE_PATH"):
                        state = pathlib.Path(state_path)
                        state.rmdir()
                        state.symlink_to(pathlib.Path(os.environ["FAKE_REVIEW_STATE_TARGET"]), target_is_directory=True)
                    if output := os.environ.get("FAKE_PANE_OUTPUT"):
                        print(output)
                elif sys.argv[1:3] == ["tab", "close"]:
                    if os.environ.get("FAKE_CLOSE_FAIL") == "1":
                        print("herdr: close refused", file=sys.stderr)
                        sys.exit(1)
                    print(json.dumps({{"result": {{"type": "ok"}}}}))
                else:
                    sys.exit(2)
                """
            )
        )
        herdr.chmod(0o755)

        hunk = fake_bin / "hunk"
        hunk.write_text(
            textwrap.dedent(
                f"""\
                #!{sys.executable}
                import json, os, pathlib, sys
                log = pathlib.Path(os.environ["FAKE_TOOL_LOG"])
                with log.open("a") as stream:
                    stream.write(json.dumps({{"tool": "hunk", "argv": sys.argv[1:], "cwd": os.getcwd()}}) + "\\n")
                if os.environ.get("FAKE_HUNK_QUERY_ERROR") == "1":
                    print("hunk: session daemon connection reset", file=sys.stderr)
                    sys.exit(1)
                started = pathlib.Path(os.environ["FAKE_REVIEW_STARTED"])
                active = os.environ.get("FAKE_SESSION_PREEXISTS") == "1" or started.exists()
                if not active:
                    print(json.dumps({{"sessions": []}}))
                    sys.exit(0)
                details = json.loads(started.read_text()) if started.exists() else {{
                    "cwd": os.getcwd(), "base": "a" * 40, "head": "b" * 40,
                }}
                checkout = details["cwd"]
                identity = f"{{details['base']}}...{{details['head']}}"
                session = {{
                    "sessionId": os.environ.get("FAKE_SESSION_ID", "session-1"),
                    "cwd": os.environ.get("FAKE_SESSION_CWD", checkout),
                    "repoRoot": os.environ.get("FAKE_SESSION_REPO_ROOT", checkout),
                    "sourceLabel": os.environ.get("FAKE_SESSION_SOURCE_LABEL", checkout),
                    "inputKind": os.environ.get("FAKE_SESSION_INPUT_KIND", "vcs"),
                    "title": os.environ.get("FAKE_SESSION_TITLE", f"{{pathlib.Path(checkout).name}} {{identity}}"),
                }}
                if os.environ.get("FAKE_SESSION_MALFORMED") == "1":
                    session.pop("repoRoot")
                sessions = [session]
                if os.environ.get("FAKE_SESSION_MULTIPLE") == "1":
                    sessions.append(session | {{"sessionId": "session-2"}})
                print(json.dumps({{"sessions": sessions}}))
                """
            )
        )
        hunk.chmod(0o755)

        return {
            "PATH": f"{fake_bin}{os.pathsep}{os.environ['PATH']}",
            "HERDR_ENV": "1",
            "HERDR_WORKSPACE_ID": "w1",
            "FAKE_TOOL_LOG": str(log),
            "FAKE_REVIEW_STARTED": str(started),
            "DEVFLOW_HUNK_TIMEOUT": "0.5",
            "DEVFLOW_HUNK_POLL_INTERVAL": "0.01",
        }, log

class StartTests(RepoCase):
    def test_repository_state_directory_symlink_fails_without_external_writes(self) -> None:
        common = Path(git(self.repo, "rev-parse", "--path-format=absolute", "--git-common-dir"))
        external = self.root / "external-state"
        external.mkdir()
        (common / "devflow").symlink_to(external)

        refused = self.devflow("--json", "start", "unsafe-state")

        self.assertEqual(refused.returncode, 2)
        self.assertEqual(json_output(refused)["error"]["code"], "workflow_state_unsafe")
        self.assertEqual(git(self.repo, "branch", "--show-current"), "main")
        self.assertEqual(list(external.iterdir()), [])

    def test_start_uses_only_the_invoking_checkout_without_a_policy(self) -> None:
        git(self.repo, "config", "--local", "devflow.worktree-mode", "managed")
        worktrees_before = git(self.repo, "worktree", "list", "--porcelain")

        started = self.devflow("--json", "start", "typed-engine")

        self.assertEqual(started.returncode, 0, started.stderr)
        payload = json_output(started)
        self.assertEqual(Path(payload["cwd"]), self.repo.resolve())
        self.assertNotIn("policy", payload)
        self.assertEqual(git(self.repo, "branch", "--show-current"), "wip/typed-engine")
        worktrees_after = git(self.repo, "worktree", "list", "--porcelain")
        before_paths = [line for line in worktrees_before.splitlines() if line.startswith("worktree ")]
        after_paths = [line for line in worktrees_after.splitlines() if line.startswith("worktree ")]
        self.assertEqual(after_paths, before_paths)

    def test_start_refuses_to_move_to_a_wip_checked_out_elsewhere(self) -> None:
        git(self.repo, "branch", "wip/elsewhere", "main")
        elsewhere = self.root / "user-wip"
        git(self.repo, "worktree", "add", str(elsewhere), "wip/elsewhere")
        worktrees_before = git(self.repo, "worktree", "list", "--porcelain")

        refused = self.devflow("--json", "start", "elsewhere")

        self.assertEqual(refused.returncode, 2)
        error = json_output(refused)["error"]
        self.assertEqual(error["code"], "checkout_conflict")
        self.assertIn(str(elsewhere), error["message"])
        self.assertEqual(git(self.repo, "branch", "--show-current"), "main")
        self.assertEqual(git(self.repo, "worktree", "list", "--porcelain"), worktrees_before)

    def test_in_place_start_preserves_ignored_file_that_collides_with_target(self) -> None:
        (self.repo / ".gitignore").write_text("collision.txt\n")
        git(self.repo, "add", ".gitignore")
        git(self.repo, "commit", "-m", "Ignore local collision")
        main_oid = git(self.repo, "rev-parse", "main")
        git(self.repo, "switch", "-c", "wip/collision")
        (self.repo / "collision.txt").write_text("tracked by feature\n")
        git(self.repo, "add", "--force", "collision.txt")
        git(self.repo, "commit", "-m", "Track colliding path")
        wip_oid = git(self.repo, "rev-parse", "HEAD")
        git(self.repo, "switch", "main")
        collision = self.repo / "collision.txt"
        collision.write_text("user-owned ignored bytes\n")

        refused = self.devflow("--json", "start", "collision")

        self.assertEqual(refused.returncode, 2)
        self.assertEqual(json_output(refused)["error"]["code"], "checkout_conflict")
        self.assertEqual(git(self.repo, "branch", "--show-current"), "main")
        self.assertEqual(git(self.repo, "rev-parse", "HEAD"), main_oid)
        self.assertEqual(git(self.repo, "rev-parse", "wip/collision"), wip_oid)
        self.assertEqual(collision.read_text(), "user-owned ignored bytes\n")

    def test_in_place_start_allows_non_colliding_ignored_file(self) -> None:
        (self.repo / ".gitignore").write_text("local-only.txt\n")
        git(self.repo, "add", ".gitignore")
        git(self.repo, "commit", "-m", "Ignore local artifact")
        git(self.repo, "switch", "-c", "wip/non-collision")
        (self.repo / "feature.txt").write_text("feature\n")
        git(self.repo, "add", "feature.txt")
        git(self.repo, "commit", "-m", "Add feature")
        git(self.repo, "switch", "main")
        local_only = self.repo / "local-only.txt"
        local_only.write_text("preserve me\n")

        started = self.devflow("--json", "start", "non-collision")

        self.assertEqual(started.returncode, 0, started.stderr)
        self.assertEqual(git(self.repo, "branch", "--show-current"), "wip/non-collision")
        self.assertEqual(local_only.read_text(), "preserve me\n")


class ReviewTests(RepoCase):
    def test_local_review_records_exact_snapshot_and_launches_shared_surface(self) -> None:
        self.assertEqual(self.devflow("start", "typed-engine").returncode, 0)
        (self.repo / "engine.py").write_text("VALUE = 1\n")
        git(self.repo, "add", "engine.py")
        git(self.repo, "commit", "-m", "Add engine")
        head = git(self.repo, "rev-parse", "HEAD")
        base = git(self.repo, "rev-parse", "main")
        tree = git(self.repo, "rev-parse", "HEAD^{tree}")
        review_env, log = self.fake_review_tools()

        reviewed = self.devflow("--json", "review", env=review_env)

        self.assertEqual(reviewed.returncode, 0, reviewed.stderr)
        payload = json_output(reviewed)
        self.assertEqual(payload["change_set"]["base_oid"], base)
        self.assertEqual(payload["change_set"]["head_oid"], head)
        self.assertEqual(payload["change_set"]["tree_oid"], tree)
        self.assertEqual(payload["review_ref"], "refs/heads/review/typed-engine")
        self.assertEqual(payload["tab_id"], "w1:t9")
        self.assertEqual(payload["pane_id"], "w1:p9")
        self.assertEqual(payload["session_id"], "session-1")
        self.assertEqual(git(self.repo, "rev-parse", "review/typed-engine"), head)

        calls = [json.loads(line) for line in log.read_text().splitlines()]
        tab = next(call for call in calls if call["tool"] == "herdr" and call["argv"][:2] == ["tab", "create"])
        self.assertEqual(
            tab["argv"],
            [
                "tab",
                "create",
                "--workspace",
                "w1",
                "--cwd",
                str(self.repo.resolve()),
                "--label",
                "review/typed-engine",
                "--env",
                f"DEVFLOW_REVIEW_BASE_OID={base}",
                "--env",
                f"DEVFLOW_REVIEW_HEAD_OID={head}",
                "--focus",
            ],
        )
        pane = next(call for call in calls if call["tool"] == "herdr" and call["argv"][:2] == ["pane", "run"])
        self.assertEqual(pane["argv"], ["pane", "run", "w1:p9", "nvim", "+HunkReview"])
        self.assertEqual(pane["base"], base)
        self.assertEqual(pane["head"], head)

        common = Path(git(self.repo, "rev-parse", "--path-format=absolute", "--git-common-dir"))
        record = json.loads((common / "devflow" / "reviews" / f"{payload['review_id']}.json").read_text())
        self.assertEqual(record["head_oid"], head)
        self.assertEqual(record["session_id"], "session-1")

    def test_external_review_requires_and_preserves_explicit_change_set(self) -> None:
        base = git(self.repo, "rev-parse", "main")
        git(self.repo, "switch", "-c", "contributor")
        (self.repo / "external.txt").write_text("external\n")
        git(self.repo, "add", "external.txt")
        git(self.repo, "commit", "-m", "External change")
        head = git(self.repo, "rev-parse", "HEAD")
        git(self.repo, "switch", "main")
        review_env, _ = self.fake_review_tools()

        incomplete = self.devflow("--json", "review", "--source", "contributor", env=review_env)
        self.assertEqual(incomplete.returncode, 2)
        self.assertEqual(json_output(incomplete)["error"]["code"], "external_change_set_incomplete")

        mismatched = self.devflow(
            "--json", "review", "--source", "contributor", "--base", base, "--name", "upstream", env=review_env
        )
        self.assertEqual(mismatched.returncode, 2)
        self.assertEqual(json_output(mismatched)["error"]["code"], "review_source_checkout_mismatch")
        self.assertFalse(Path(review_env["FAKE_REVIEW_STARTED"]).exists())

        git(self.repo, "switch", "--detach", head)
        reviewed = self.devflow(
            "--json", "review", "--source", "contributor", "--base", base, "--name", "upstream", env=review_env
        )
        self.assertEqual(reviewed.returncode, 0, reviewed.stderr)
        payload = json_output(reviewed)
        self.assertEqual(payload["change_set"]["source"], "contributor")
        self.assertEqual(payload["change_set"]["base_oid"], base)
        self.assertEqual(payload["change_set"]["head_oid"], head)
        self.assertEqual(Path(payload["checkout"]), self.repo.resolve())
        self.assertEqual(git(self.repo, "rev-parse", "review/upstream"), head)

    def test_complete_explicit_triple_is_external_even_when_source_is_named_wip(self) -> None:
        base = git(self.repo, "rev-parse", "main")
        git(self.repo, "switch", "-c", "wip/upstream")
        (self.repo / "external.txt").write_text("external\n")
        git(self.repo, "add", "external.txt")
        git(self.repo, "commit", "-m", "External change")
        head = git(self.repo, "rev-parse", "HEAD")
        review_env, _ = self.fake_review_tools()

        reviewed = self.devflow(
            "--json",
            "review",
            "--source",
            "wip/upstream",
            "--base",
            base,
            "--name",
            "vendor-change",
            env=review_env,
        )

        self.assertEqual(reviewed.returncode, 0, reviewed.stderr)
        payload = json_output(reviewed)
        self.assertEqual(payload["name"], "vendor-change")
        self.assertEqual(payload["change_set"]["kind"], "external")
        self.assertEqual(payload["change_set"]["source"], "wip/upstream")
        self.assertEqual(payload["change_set"]["head_oid"], head)

    def test_external_review_rejects_a_base_that_is_not_head_ancestor(self) -> None:
        git(self.repo, "switch", "-c", "source", "main")
        (self.repo / "source.txt").write_text("source\n")
        git(self.repo, "add", "source.txt")
        git(self.repo, "commit", "-m", "Source")
        git(self.repo, "switch", "-c", "sibling", "main")
        (self.repo / "sibling.txt").write_text("sibling\n")
        git(self.repo, "add", "sibling.txt")
        git(self.repo, "commit", "-m", "Sibling")
        sibling = git(self.repo, "rev-parse", "HEAD")
        review_env, _ = self.fake_review_tools()

        refused = self.devflow(
            "--json",
            "review",
            "--source",
            "source",
            "--base",
            sibling,
            "--name",
            "diverged",
            env=review_env,
        )

        self.assertEqual(refused.returncode, 2)
        self.assertEqual(json_output(refused)["error"]["code"], "external_base_not_ancestor")
        self.assertFalse((self.root / "review-started").exists())

    def test_failed_ui_keeps_snapshot_ref_closes_created_tab_and_writes_no_review_record(self) -> None:
        self.assertEqual(self.devflow("start", "failed-ui").returncode, 0)
        (self.repo / "feature.txt").write_text("review me\n")
        git(self.repo, "add", "feature.txt")
        git(self.repo, "commit", "-m", "Review me")
        head = git(self.repo, "rev-parse", "HEAD")
        review_env, log = self.fake_review_tools()

        failed = self.devflow("--json", "review", env=review_env | {"FAKE_PANE_FAIL": "1"})

        self.assertEqual(failed.returncode, 2)
        self.assertEqual(json_output(failed)["error"]["code"], "herdr_pane_run_failed")
        self.assertEqual(git(self.repo, "rev-parse", "review/failed-ui"), head)
        calls = [json.loads(line) for line in log.read_text().splitlines()]
        closes = [call for call in calls if call["tool"] == "herdr" and call["argv"][:2] == ["tab", "close"]]
        self.assertEqual([call["argv"] for call in closes], [["tab", "close", "w1:t9"]])
        common = Path(git(self.repo, "rev-parse", "--path-format=absolute", "--git-common-dir"))
        reviews = common / "devflow" / "reviews"
        self.assertFalse(reviews.exists() and any(reviews.iterdir()))

    def test_failed_tab_cleanup_preserves_the_original_error_and_reports_cleanup(self) -> None:
        self.assertEqual(self.devflow("start", "cleanup-failure").returncode, 0)
        (self.repo / "feature.txt").write_text("review me\n")
        git(self.repo, "add", "feature.txt")
        git(self.repo, "commit", "-m", "Review me")
        review_env, log = self.fake_review_tools()

        failed = self.devflow(
            "--json",
            "review",
            env=review_env | {"FAKE_PANE_FAIL": "1", "FAKE_CLOSE_FAIL": "1"},
        )

        self.assertEqual(failed.returncode, 2)
        error = json_output(failed)["error"]
        self.assertEqual(error["code"], "herdr_pane_run_failed")
        self.assertIn("pane_failed", error["message"])
        self.assertIn("close refused", error["message"])
        calls = [json.loads(line) for line in log.read_text().splitlines()]
        closes = [call for call in calls if call["tool"] == "herdr" and call["argv"][:2] == ["tab", "close"]]
        self.assertEqual([call["argv"] for call in closes], [["tab", "close", "w1:t9"]])

    def test_non_finite_poll_settings_fail_before_review_ref_or_ui_effects(self) -> None:
        self.assertEqual(self.devflow("start", "finite-polling").returncode, 0)
        (self.repo / "feature.txt").write_text("review me\n")
        git(self.repo, "add", "feature.txt")
        git(self.repo, "commit", "-m", "Review me")
        review_env, log = self.fake_review_tools()

        for variable in ("DEVFLOW_HUNK_TIMEOUT", "DEVFLOW_HUNK_POLL_INTERVAL"):
            for value in ("inf", "-inf", "nan"):
                with self.subTest(variable=variable, value=value):
                    failed = self.devflow("--json", "review", env=review_env | {variable: value})

                    self.assertEqual(failed.returncode, 2)
                    self.assertEqual(json_output(failed)["error"]["code"], "hunk_poll_settings_invalid")
                    missing = run(
                        ["git", "rev-parse", "--verify", "review/finite-polling"], cwd=self.repo, env=self.env
                    )
                    self.assertNotEqual(missing.returncode, 0)
                    if log.exists():
                        calls = [json.loads(line) for line in log.read_text().splitlines()]
                        self.assertFalse(any(call["tool"] == "herdr" for call in calls))

    def test_review_record_failure_closes_the_created_tab_and_leaves_no_external_write(self) -> None:
        self.assertEqual(self.devflow("start", "record-failure").returncode, 0)
        (self.repo / "feature.txt").write_text("review me\n")
        git(self.repo, "add", "feature.txt")
        git(self.repo, "commit", "-m", "Review me")
        common = Path(git(self.repo, "rev-parse", "--path-format=absolute", "--git-common-dir"))
        external = self.root / "external-reviews"
        external.mkdir()
        review_env, log = self.fake_review_tools()

        failed = self.devflow(
            "--json",
            "review",
            env=review_env
            | {
                "FAKE_REVIEW_STATE_PATH": str(common / "devflow" / "reviews"),
                "FAKE_REVIEW_STATE_TARGET": str(external),
            },
        )

        self.assertEqual(failed.returncode, 2)
        self.assertEqual(json_output(failed)["error"]["code"], "workflow_state_unsafe")
        calls = [json.loads(line) for line in log.read_text().splitlines()]
        closes = [call for call in calls if call["tool"] == "herdr" and call["argv"][:2] == ["tab", "close"]]
        self.assertEqual([call["argv"] for call in closes], [["tab", "close", "w1:t9"]])
        self.assertEqual(list(external.iterdir()), [])

    def test_nonempty_pane_success_response_closes_only_created_tab(self) -> None:
        self.assertEqual(self.devflow("start", "invalid-ui").returncode, 0)
        (self.repo / "feature.txt").write_text("review me\n")
        git(self.repo, "add", "feature.txt")
        git(self.repo, "commit", "-m", "Review me")
        review_env, log = self.fake_review_tools()

        failed = self.devflow("--json", "review", env=review_env | {"FAKE_PANE_OUTPUT": "unexpected"})

        self.assertEqual(failed.returncode, 2)
        self.assertEqual(json_output(failed)["error"]["code"], "herdr_invalid_response")
        calls = [json.loads(line) for line in log.read_text().splitlines()]
        closes = [call for call in calls if call["tool"] == "herdr" and call["argv"][:2] == ["tab", "close"]]
        self.assertEqual([call["argv"] for call in closes], [["tab", "close", "w1:t9"]])

    def test_unrelated_hunk_session_after_launch_fails_closed_and_closes_created_tab(self) -> None:
        self.assertEqual(self.devflow("start", "wrong-session").returncode, 0)
        (self.repo / "feature.txt").write_text("review me\n")
        git(self.repo, "add", "feature.txt")
        git(self.repo, "commit", "-m", "Review exact aggregate")
        head = git(self.repo, "rev-parse", "HEAD")
        base = git(self.repo, "rev-parse", "main")
        review_env, log = self.fake_review_tools()

        failed = self.devflow(
            "--json",
            "review",
            env=review_env | {"FAKE_SESSION_TITLE": f"unrelated {base}...{head}"},
        )

        self.assertEqual(failed.returncode, 2)
        self.assertEqual(json_output(failed)["error"]["code"], "hunk_session_mismatch")
        self.assertEqual(git(self.repo, "rev-parse", "review/wrong-session"), head)
        calls = [json.loads(line) for line in log.read_text().splitlines()]
        closes = [call for call in calls if call["tool"] == "herdr" and call["argv"][:2] == ["tab", "close"]]
        self.assertEqual([call["argv"] for call in closes], [["tab", "close", "w1:t9"]])

    def test_malformed_hunk_session_after_launch_fails_closed_and_closes_created_tab(self) -> None:
        self.assertEqual(self.devflow("start", "malformed-session").returncode, 0)
        (self.repo / "feature.txt").write_text("review me\n")
        git(self.repo, "add", "feature.txt")
        git(self.repo, "commit", "-m", "Review exact aggregate")
        review_env, log = self.fake_review_tools()

        failed = self.devflow("--json", "review", env=review_env | {"FAKE_SESSION_MALFORMED": "1"})

        self.assertEqual(failed.returncode, 2)
        self.assertEqual(json_output(failed)["error"]["code"], "hunk_invalid_response")
        calls = [json.loads(line) for line in log.read_text().splitlines()]
        closes = [call for call in calls if call["tool"] == "herdr" and call["argv"][:2] == ["tab", "close"]]
        self.assertEqual([call["argv"] for call in closes], [["tab", "close", "w1:t9"]])

    def test_hunk_session_query_error_is_not_treated_as_absence(self) -> None:
        self.assertEqual(self.devflow("start", "query-error").returncode, 0)
        (self.repo / "feature.txt").write_text("review me\n")
        git(self.repo, "add", "feature.txt")
        git(self.repo, "commit", "-m", "Review exact aggregate")
        review_env, log = self.fake_review_tools()

        failed = self.devflow("--json", "review", env=review_env | {"FAKE_HUNK_QUERY_ERROR": "1"})

        self.assertEqual(failed.returncode, 2)
        self.assertEqual(json_output(failed)["error"]["code"], "hunk_session_query_failed")
        calls = [json.loads(line) for line in log.read_text().splitlines()]
        self.assertFalse(any(call["tool"] == "herdr" for call in calls))
        missing = run(["git", "rev-parse", "--verify", "review/query-error"], cwd=self.repo, env=self.env)
        self.assertNotEqual(missing.returncode, 0)

    def test_exact_hunk_session_registered_after_launch_is_accepted(self) -> None:
        self.assertEqual(self.devflow("start", "exact-session").returncode, 0)
        (self.repo / "feature.txt").write_text("review me\n")
        git(self.repo, "add", "feature.txt")
        git(self.repo, "commit", "-m", "Review exact aggregate")
        review_env, _ = self.fake_review_tools()

        reviewed = self.devflow("--json", "review", env=review_env | {"FAKE_SESSION_ID": "concurrent-exact-session"})

        self.assertEqual(reviewed.returncode, 0, reviewed.stderr)
        self.assertEqual(json_output(reviewed)["session_id"], "concurrent-exact-session")

    def test_concurrent_review_commands_are_serialized_before_session_preflight(self) -> None:
        self.assertEqual(self.devflow("start", "serialized").returncode, 0)
        (self.repo / "feature.txt").write_text("review me\n")
        git(self.repo, "add", "feature.txt")
        git(self.repo, "commit", "-m", "Review me")
        review_env, _ = self.fake_review_tools()
        process_env = os.environ.copy() | self.env | review_env | {"FAKE_PANE_DELAY": "0.3"}
        argv = [str(DEVFLOW), "--json", "review"]

        first = subprocess.Popen(
            argv, cwd=self.repo, env=process_env, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
        )
        second = subprocess.Popen(
            argv, cwd=self.repo, env=process_env, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
        )
        first_stdout, first_stderr = first.communicate(timeout=5)
        second_stdout, second_stderr = second.communicate(timeout=5)

        results = [(first.returncode, first_stdout, first_stderr), (second.returncode, second_stdout, second_stderr)]
        self.assertEqual(sorted(result[0] for result in results), [0, 2])
        refused = next(json.loads(stdout) for code, stdout, _ in results if code == 2)
        self.assertEqual(refused["error"]["code"], "workflow_busy")

    def test_review_uses_the_invoking_checkout_without_creating_a_worktree(self) -> None:
        worktrees_before = git(self.repo, "worktree", "list", "--porcelain")
        started = self.devflow("--json", "start", "in-place-review")
        self.assertEqual(Path(json_output(started)["cwd"]), self.repo.resolve())
        (self.repo / "feature.txt").write_text("in place\n")
        git(self.repo, "add", "feature.txt")
        git(self.repo, "commit", "-m", "In-place feature")
        head = git(self.repo, "rev-parse", "HEAD")
        review_env, _ = self.fake_review_tools()

        reviewed = self.devflow("--json", "review", env=review_env)

        self.assertEqual(reviewed.returncode, 0, reviewed.stderr)
        checkout = Path(json_output(reviewed)["checkout"])
        self.assertEqual(checkout, self.repo.resolve())
        self.assertEqual(git(checkout, "rev-parse", "HEAD"), head)
        self.assertEqual(git(checkout, "branch", "--show-current"), "wip/in-place-review")
        before_paths = [line for line in worktrees_before.splitlines() if line.startswith("worktree ")]
        after = git(self.repo, "worktree", "list", "--porcelain")
        after_paths = [line for line in after.splitlines() if line.startswith("worktree ")]
        self.assertEqual(after_paths, before_paths)

    def test_existing_session_is_rejected_before_review_ref_advances(self) -> None:
        self.assertEqual(self.devflow("start", "active-review").returncode, 0)
        (self.repo / "feature.txt").write_text("first\n")
        git(self.repo, "add", "feature.txt")
        git(self.repo, "commit", "-m", "First version")
        first_head = git(self.repo, "rev-parse", "HEAD")
        review_env, _ = self.fake_review_tools()
        first = self.devflow("--json", "review", env=review_env)
        self.assertEqual(first.returncode, 0, first.stderr)
        (self.repo / "feature.txt").write_text("second\n")
        git(self.repo, "add", "feature.txt")
        git(self.repo, "commit", "-m", "Second version")

        refused = self.devflow("--json", "review", env=review_env | {"FAKE_SESSION_PREEXISTS": "1"})

        self.assertEqual(refused.returncode, 2)
        self.assertEqual(json_output(refused)["error"]["code"], "hunk_session_exists")
        self.assertEqual(git(self.repo, "rev-parse", "review/active-review"), first_head)

    def test_review_ref_does_not_advance_while_checked_out_in_a_user_worktree(self) -> None:
        (self.repo / ".gitignore").write_text("local-review-state.txt\n")
        git(self.repo, "add", ".gitignore")
        git(self.repo, "commit", "-m", "Ignore review-local state")
        reviewed_head = git(self.repo, "rev-parse", "main")
        git(self.repo, "branch", "review/checked-review", reviewed_head)
        user_review = self.root / "user-review"
        git(self.repo, "worktree", "add", str(user_review), "review/checked-review")
        local_state = user_review / "local-review-state.txt"
        local_state.write_text("preserve me\n")

        self.assertEqual(self.devflow("start", "checked-review").returncode, 0)
        (self.repo / "local-review-state.txt").write_text("feature version\n")
        git(self.repo, "add", "--force", "local-review-state.txt")
        git(self.repo, "commit", "-m", "Feature version")
        review_env, _ = self.fake_review_tools()

        refused = self.devflow("--json", "review", env=review_env)

        self.assertEqual(refused.returncode, 2)
        self.assertEqual(json_output(refused)["error"]["code"], "review_checkout_conflict")
        self.assertEqual(git(self.repo, "rev-parse", "review/checked-review"), reviewed_head)
        self.assertEqual(git(user_review, "rev-parse", "HEAD"), reviewed_head)
        self.assertEqual(git(user_review, "status", "--porcelain"), "")
        self.assertEqual(local_state.read_text(), "preserve me\n")
        self.assertFalse(Path(review_env["FAKE_REVIEW_STARTED"]).exists())

    def test_review_ref_checked_out_at_exact_snapshot_needs_no_movement(self) -> None:
        git(self.repo, "switch", "-c", "wip/exact-review")
        (self.repo / "feature.txt").write_text("exact\n")
        git(self.repo, "add", "feature.txt")
        git(self.repo, "commit", "-m", "Exact review snapshot")
        head = git(self.repo, "rev-parse", "HEAD")
        git(self.repo, "branch", "review/exact-review", head)
        user_review = self.root / "exact-user-review"
        git(self.repo, "worktree", "add", str(user_review), "review/exact-review")
        review_env, _ = self.fake_review_tools()

        reviewed = self.devflow("--json", "review", env=review_env)

        self.assertEqual(reviewed.returncode, 0, reviewed.stderr)
        self.assertEqual(json_output(reviewed)["change_set"]["head_oid"], head)
        self.assertEqual(git(user_review, "rev-parse", "HEAD"), head)

    def test_plain_review_output_is_the_approval_identifier(self) -> None:
        self.assertEqual(self.devflow("start", "plain-review").returncode, 0)
        (self.repo / "feature.txt").write_text("plain\n")
        git(self.repo, "add", "feature.txt")
        git(self.repo, "commit", "-m", "Plain review")
        review_env, _ = self.fake_review_tools()

        reviewed = self.devflow("review", env=review_env)

        self.assertEqual(reviewed.returncode, 0, reviewed.stderr)
        review_id = reviewed.stdout.strip()
        self.assertRegex(review_id, r"^[0-9a-f]{24}$")
        common = Path(git(self.repo, "rev-parse", "--path-format=absolute", "--git-common-dir"))
        self.assertTrue((common / "devflow" / "reviews" / f"{review_id}.json").is_file())

    def test_wip_must_include_current_main_and_be_clean(self) -> None:
        self.assertEqual(self.devflow("start", "main-merge").returncode, 0)
        (self.repo / "feature.txt").write_text("feature\n")
        git(self.repo, "add", "feature.txt")
        git(self.repo, "commit", "-m", "Feature")
        old_main = git(self.repo, "rev-parse", "main")
        git(self.repo, "switch", "--detach", "main")
        (self.repo / "concurrent.txt").write_text("advance\n")
        git(self.repo, "add", "concurrent.txt")
        git(self.repo, "commit", "-m", "Advance main")
        advanced_main = git(self.repo, "rev-parse", "HEAD")
        git(self.repo, "update-ref", "refs/heads/main", advanced_main, old_main)
        git(self.repo, "switch", "wip/main-merge")
        review_env, _ = self.fake_review_tools()

        missing_merge = self.devflow("--json", "review", env=review_env)
        self.assertEqual(missing_merge.returncode, 2)
        self.assertEqual(json_output(missing_merge)["error"]["code"], "wip_requires_main_merge")

        git(self.repo, "merge", "--no-edit", "main")
        (self.repo / "untracked.txt").write_text("dirty\n")
        dirty = self.devflow("--json", "review", env=review_env)
        self.assertEqual(dirty.returncode, 2)
        self.assertEqual(json_output(dirty)["error"]["code"], "dirty_checkout")
        (self.repo / "untracked.txt").unlink()
        reviewed = self.devflow("--json", "review", env=review_env)
        self.assertEqual(reviewed.returncode, 0, reviewed.stderr)

    def test_sha256_repository_uses_full_width_compare_and_swap_oids(self) -> None:
        sha_repo = self.root / "sha256"
        sha_repo.mkdir()
        initialized = run(["git", "init", "--object-format=sha256", "-b", "main"], cwd=sha_repo)
        if initialized.returncode != 0:
            self.skipTest("Git was built without SHA-256 repository support")
        git(sha_repo, "config", "user.name", "Devflow Test")
        git(sha_repo, "config", "user.email", "devflow@example.test")
        (sha_repo / "README.md").write_text("sha256\n")
        git(sha_repo, "add", "README.md")
        git(sha_repo, "commit", "-m", "Initial")
        self.assertEqual(self.devflow("start", "wide-oids", cwd=sha_repo).returncode, 0)
        (sha_repo / "feature.txt").write_text("wide\n")
        git(sha_repo, "add", "feature.txt")
        git(sha_repo, "commit", "-m", "Wide OIDs")
        review_env, _ = self.fake_review_tools()

        reviewed = self.devflow("--json", "review", cwd=sha_repo, env=review_env)

        self.assertEqual(reviewed.returncode, 0, reviewed.stderr)
        payload = json_output(reviewed)
        self.assertEqual(len(payload["change_set"]["base_oid"]), 64)
        self.assertEqual(len(payload["change_set"]["head_oid"]), 64)
        self.assertEqual(git(sha_repo, "rev-parse", "review/wide-oids"), payload["change_set"]["head_oid"])


class LandingTests(RepoCase):
    def _reviewed_feature(self) -> tuple[str, str, dict[str, str]]:
        self.assertEqual(self.devflow("start", "landing").returncode, 0)
        (self.repo / "feature.txt").write_text("feature\n")
        git(self.repo, "add", "feature.txt")
        git(self.repo, "commit", "-m", "Feature part one")
        (self.repo / "feature.txt").write_text("feature complete\n")
        git(self.repo, "add", "feature.txt")
        git(self.repo, "commit", "-m", "Complete feature")
        head = git(self.repo, "rev-parse", "HEAD")
        review_env, _ = self.fake_review_tools()
        reviewed = self.devflow("--json", "review", env=review_env)
        self.assertEqual(reviewed.returncode, 0, reviewed.stderr)
        return json_output(reviewed)["review_id"], head, review_env

    def test_landing_requires_an_explicit_target(self) -> None:
        review_id, _, _ = self._reviewed_feature()
        main_before = git(self.repo, "rev-parse", "main")

        missing = self.devflow(
            "--json", "land", "landing", "--approved", review_id, "--title", "Land explicit feature"
        )

        self.assertEqual(missing.returncode, 2)
        self.assertIn("--target", missing.stderr)
        self.assertEqual(git(self.repo, "rev-parse", "main"), main_before)

    def test_landing_updates_only_the_explicit_target_when_multiple_mainlines_exist(self) -> None:
        review_id, _, _ = self._reviewed_feature()
        main_before = git(self.repo, "rev-parse", "main")
        git(self.repo, "branch", "mainline", main_before)

        landed = self.devflow(
            "--json",
            "land",
            "landing",
            "--target",
            "mainline",
            "--approved",
            review_id,
            "--title",
            "Land explicit feature",
        )

        self.assertEqual(landed.returncode, 0, landed.stderr)
        self.assertEqual(json_output(landed)["mainline_ref"], "refs/heads/mainline")
        self.assertEqual(git(self.repo, "rev-parse", "main"), main_before)
        self.assertNotEqual(git(self.repo, "rev-parse", "mainline"), main_before)

    def test_landing_does_not_fall_back_when_the_explicit_target_is_missing(self) -> None:
        review_id, _, _ = self._reviewed_feature()
        main_before = git(self.repo, "rev-parse", "main")

        refused = self.devflow(
            "--json",
            "land",
            "landing",
            "--target",
            "master",
            "--approved",
            review_id,
            "--title",
            "Land explicit feature",
        )

        self.assertEqual(refused.returncode, 2)
        self.assertEqual(json_output(refused)["error"]["code"], "mainline_not_found")
        self.assertEqual(git(self.repo, "rev-parse", "main"), main_before)

    def test_landing_applies_approved_snapshot_to_advanced_main_as_one_commit(self) -> None:
        review_id, wip_head, _ = self._reviewed_feature()
        review_head = git(self.repo, "rev-parse", "review/landing")
        old_main = git(self.repo, "rev-parse", "main")

        concurrent = self.root / "concurrent-main"
        git(self.repo, "worktree", "add", "--detach", str(concurrent), "main")
        (concurrent / "concurrent.txt").write_text("concurrent\n")
        git(concurrent, "add", "concurrent.txt")
        git(concurrent, "commit", "-m", "Concurrent change")
        advanced_main = git(concurrent, "rev-parse", "HEAD")
        git(self.repo, "worktree", "remove", str(concurrent))
        git(self.repo, "update-ref", "refs/heads/main", advanced_main, old_main)

        landed = self.devflow(
            "--json",
            "land",
            "landing",
            "--target",
            "main",
            "--approved",
            review_id,
            "--title",
            "Add deterministic workflow engine",
        )

        self.assertEqual(landed.returncode, 0, landed.stderr)
        payload = json_output(landed)
        landed_oid = git(self.repo, "rev-parse", "main")
        self.assertEqual(payload["commit_oid"], landed_oid)
        self.assertEqual(git(self.repo, "show", "-s", "--format=%s", landed_oid), "Add deterministic workflow engine")
        self.assertEqual(git(self.repo, "show", "-s", "--format=%P", landed_oid), advanced_main)
        self.assertEqual(git(self.repo, "show", "main:feature.txt"), "feature complete")
        self.assertEqual(git(self.repo, "show", "main:concurrent.txt"), "concurrent")
        self.assertEqual(git(self.repo, "rev-parse", "wip/landing"), wip_head)
        self.assertEqual(git(self.repo, "rev-parse", "review/landing"), review_head)

    def test_new_wip_commit_stales_approval(self) -> None:
        review_id, reviewed_head, _ = self._reviewed_feature()
        (self.repo / "after-review.txt").write_text("changed\n")
        git(self.repo, "add", "after-review.txt")
        git(self.repo, "commit", "-m", "Change after review")
        main_before = git(self.repo, "rev-parse", "main")

        refused = self.devflow(
            "--json", "land", "landing", "--target", "main", "--approved", review_id, "--title", "Stale"
        )

        self.assertEqual(refused.returncode, 2)
        self.assertEqual(json_output(refused)["error"]["code"], "approval_stale")
        self.assertEqual(git(self.repo, "rev-parse", "main"), main_before)
        self.assertEqual(git(self.repo, "rev-parse", "review/landing"), reviewed_head)

    def test_dirty_review_checkout_blocks_landing(self) -> None:
        review_id, reviewed_head, _ = self._reviewed_feature()
        (self.repo / "unreviewed.txt").write_text("not reviewed\n")
        main_before = git(self.repo, "rev-parse", "main")

        refused = self.devflow(
            "--json",
            "land",
            "landing",
            "--target",
            "main",
            "--approved",
            review_id,
            "--title",
            "Reject dirty checkout",
        )

        self.assertEqual(refused.returncode, 2)
        self.assertEqual(json_output(refused)["error"]["code"], "dirty_checkout")
        self.assertEqual(git(self.repo, "rev-parse", "main"), main_before)
        self.assertEqual(git(self.repo, "rev-parse", "review/landing"), reviewed_head)

    def test_detached_review_checkout_blocks_landing_even_at_the_reviewed_head(self) -> None:
        review_id, reviewed_head, _ = self._reviewed_feature()
        git(self.repo, "switch", "--detach", reviewed_head)
        main_before = git(self.repo, "rev-parse", "main")

        refused = self.devflow(
            "--json",
            "land",
            "landing",
            "--target",
            "main",
            "--approved",
            review_id,
            "--title",
            "Reject changed checkout identity",
        )

        self.assertEqual(refused.returncode, 2)
        self.assertEqual(json_output(refused)["error"]["code"], "review_checkout_stale")
        self.assertEqual(git(self.repo, "branch", "--show-current"), "")
        self.assertEqual(git(self.repo, "rev-parse", "HEAD"), reviewed_head)
        self.assertEqual(git(self.repo, "rev-parse", "main"), main_before)
        self.assertEqual(git(self.repo, "rev-parse", "review/landing"), reviewed_head)

    def test_wip_advance_during_atomic_landing_leaves_main_unchanged(self) -> None:
        review_id, reviewed_head, review_env = self._reviewed_feature()
        main_before = git(self.repo, "rev-parse", "main")
        tree = git(self.repo, "rev-parse", f"{reviewed_head}^{{tree}}")
        raced_commit = run(
            ["git", "commit-tree", tree, "-p", reviewed_head],
            cwd=self.repo,
            env=self.env,
            stdin="Advance WIP during landing\n",
        )
        self.assertEqual(raced_commit.returncode, 0, raced_commit.stderr)
        raced_head = raced_commit.stdout.strip()

        real_git = shutil.which("git")
        self.assertIsNotNone(real_git)
        git_wrapper = self.root / "fake-bin" / "git"
        git_wrapper.write_text(
            textwrap.dedent(
                f"""\
                #!{sys.executable}
                import os, subprocess, sys
                real = os.environ["DEVFLOW_REAL_GIT"]
                if sys.argv[1:] == ["update-ref", "--stdin"]:
                    raced = subprocess.run(
                        [real, "update-ref", os.environ["DEVFLOW_RACE_REF"], os.environ["DEVFLOW_RACE_NEW"],
                         os.environ["DEVFLOW_RACE_OLD"]],
                        cwd=os.getcwd(), env=os.environ.copy(), text=True, capture_output=True, check=False,
                    )
                    if raced.returncode != 0:
                        sys.stderr.write(raced.stderr)
                        raise SystemExit(raced.returncode)
                os.execv(real, [real, *sys.argv[1:]])
                """
            )
        )
        git_wrapper.chmod(0o755)
        race_env = review_env | {
            "DEVFLOW_REAL_GIT": str(real_git),
            "DEVFLOW_RACE_REF": "refs/heads/wip/landing",
            "DEVFLOW_RACE_OLD": reviewed_head,
            "DEVFLOW_RACE_NEW": raced_head,
        }

        refused = self.devflow(
            "--json",
            "land",
            "landing",
            "--target",
            "main",
            "--approved",
            review_id,
            "--title",
            "Reject stale atomic landing",
            env=race_env,
        )

        self.assertEqual(refused.returncode, 2)
        self.assertEqual(json_output(refused)["error"]["code"], "approval_stale")
        self.assertEqual(git(self.repo, "rev-parse", "wip/landing"), raced_head)
        self.assertEqual(git(self.repo, "rev-parse", "review/landing"), reviewed_head)
        self.assertEqual(git(self.repo, "rev-parse", "main"), main_before)

    def test_target_advance_during_atomic_landing_is_preserved(self) -> None:
        review_id, reviewed_head, review_env = self._reviewed_feature()
        main_before = git(self.repo, "rev-parse", "main")
        main_tree = git(self.repo, "rev-parse", f"{main_before}^{{tree}}")
        raced_commit = run(
            ["git", "commit-tree", main_tree, "-p", main_before],
            cwd=self.repo,
            env=self.env,
            stdin="Advance target during landing\n",
        )
        self.assertEqual(raced_commit.returncode, 0, raced_commit.stderr)
        raced_head = raced_commit.stdout.strip()

        real_git = shutil.which("git")
        self.assertIsNotNone(real_git)
        git_wrapper = self.root / "fake-bin" / "git"
        git_wrapper.write_text(
            textwrap.dedent(
                f"""\
                #!{sys.executable}
                import os, subprocess, sys
                real = os.environ["DEVFLOW_REAL_GIT"]
                if sys.argv[1:] == ["update-ref", "--stdin"]:
                    raced = subprocess.run(
                        [real, "update-ref", os.environ["DEVFLOW_RACE_REF"], os.environ["DEVFLOW_RACE_NEW"],
                         os.environ["DEVFLOW_RACE_OLD"]],
                        cwd=os.getcwd(), env=os.environ.copy(), text=True, capture_output=True, check=False,
                    )
                    if raced.returncode != 0:
                        sys.stderr.write(raced.stderr)
                        raise SystemExit(raced.returncode)
                os.execv(real, [real, *sys.argv[1:]])
                """
            )
        )
        git_wrapper.chmod(0o755)
        race_env = review_env | {
            "DEVFLOW_REAL_GIT": str(real_git),
            "DEVFLOW_RACE_REF": "refs/heads/main",
            "DEVFLOW_RACE_OLD": main_before,
            "DEVFLOW_RACE_NEW": raced_head,
        }

        refused = self.devflow(
            "--json",
            "land",
            "landing",
            "--target",
            "main",
            "--approved",
            review_id,
            "--title",
            "Reject concurrent target advance",
            env=race_env,
        )

        self.assertEqual(refused.returncode, 2)
        self.assertEqual(json_output(refused)["error"]["code"], "ref_update_rejected")
        self.assertEqual(git(self.repo, "rev-parse", "main"), raced_head)
        self.assertEqual(git(self.repo, "rev-parse", "wip/landing"), reviewed_head)
        self.assertEqual(git(self.repo, "rev-parse", "review/landing"), reviewed_head)

    def test_landing_refuses_to_disturb_main_checked_out_in_a_user_worktree(self) -> None:
        (self.repo / ".gitignore").write_text("ignored.txt\n")
        git(self.repo, "add", ".gitignore")
        git(self.repo, "commit", "-m", "Ignore local state")
        ignored = self.repo / "ignored.txt"
        ignored.write_text("user-owned local state\n")
        git(self.repo, "branch", "wip/align-main", "main")
        wip = self.root / "user-wip"
        git(self.repo, "worktree", "add", str(wip), "wip/align-main")
        started = self.devflow("--json", "start", "align-main", cwd=wip)
        self.assertEqual(started.returncode, 0, started.stderr)
        self.assertEqual(Path(json_output(started)["cwd"]), wip.resolve())
        (wip / "ignored.txt").write_text("feature-owned state\n")
        git(wip, "add", "--force", "ignored.txt")
        git(wip, "commit", "-m", "Add ignored file")
        review_env, _ = self.fake_review_tools()
        reviewed = self.devflow("--json", "review", cwd=wip, env=review_env)
        review_id = json_output(reviewed)["review_id"]

        main_before = git(self.repo, "rev-parse", "main")
        head_before = git(self.repo, "rev-parse", "HEAD")

        landed = self.devflow(
            "--json",
            "land",
            "align-main",
            "--target",
            "main",
            "--approved",
            review_id,
            "--title",
            "Align main checkout",
            cwd=wip,
        )

        self.assertEqual(landed.returncode, 2)
        self.assertEqual(json_output(landed)["error"]["code"], "mainline_checkout_conflict")
        self.assertEqual(git(self.repo, "branch", "--show-current"), "main")
        self.assertEqual(git(self.repo, "rev-parse", "HEAD"), head_before)
        self.assertEqual(git(self.repo, "rev-parse", "main"), main_before)
        self.assertEqual(ignored.read_text(), "user-owned local state\n")

    def test_conflicting_main_advance_is_refused_without_moving_main(self) -> None:
        self.assertEqual(self.devflow("start", "conflict").returncode, 0)
        (self.repo / "README.md").write_text("feature version\n")
        git(self.repo, "add", "README.md")
        git(self.repo, "commit", "-m", "Feature edit")
        review_env, _ = self.fake_review_tools()
        reviewed = self.devflow("--json", "review", env=review_env)
        review_id = json_output(reviewed)["review_id"]
        old_main = git(self.repo, "rev-parse", "main")
        concurrent = self.root / "conflicting-main"
        git(self.repo, "worktree", "add", "--detach", str(concurrent), "main")
        (concurrent / "README.md").write_text("main version\n")
        git(concurrent, "add", "README.md")
        git(concurrent, "commit", "-m", "Main edit")
        advanced_main = git(concurrent, "rev-parse", "HEAD")
        git(self.repo, "worktree", "remove", str(concurrent))
        git(self.repo, "update-ref", "refs/heads/main", advanced_main, old_main)

        refused = self.devflow(
            "--json",
            "land",
            "conflict",
            "--target",
            "main",
            "--approved",
            review_id,
            "--title",
            "Conflicting feature",
        )

        self.assertEqual(refused.returncode, 2)
        self.assertEqual(json_output(refused)["error"]["code"], "landing_conflict")
        self.assertEqual(git(self.repo, "rev-parse", "main"), advanced_main)

    def test_same_approval_cannot_land_twice(self) -> None:
        review_id, _, _ = self._reviewed_feature()
        first = self.devflow(
            "land", "landing", "--target", "main", "--approved", review_id, "--title", "Land once"
        )
        self.assertEqual(first.returncode, 0, first.stderr)
        main_after_first = git(self.repo, "rev-parse", "main")
        self.assertEqual(first.stdout.strip(), main_after_first)

        repeated = self.devflow(
            "--json", "land", "landing", "--target", "main", "--approved", review_id, "--title", "Land twice"
        )

        self.assertEqual(repeated.returncode, 2)
        self.assertEqual(json_output(repeated)["error"]["code"], "landing_already_applied")
        self.assertEqual(git(self.repo, "rev-parse", "main"), main_after_first)


class HarnessTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.home = self.root / "home"
        self.home.mkdir()
        self.env = {"HOME": str(self.home), "CODEX_HOME": str(self.root / "codex")}

    def tearDown(self) -> None:
        self.temp.cleanup()

    def devflow(self, *args: str) -> subprocess.CompletedProcess[str]:
        return run([str(DEVFLOW), *args], cwd=self.root, env=self.env)

    def test_install_status_remove_preserve_outside_bytes_and_mode(self) -> None:
        target = Path(self.env["CODEX_HOME"]) / "AGENTS.md"
        target.parent.mkdir()
        original = b"# Personal rules\nKeep this exact."
        target.write_bytes(original)
        target.chmod(0o640)

        installed = self.devflow("--json", "harness", "install", "codex")
        self.assertEqual(installed.returncode, 0, installed.stderr)
        self.assertEqual(json_output(installed)["status"], "installed")
        self.assertTrue(json_output(installed)["changed"])
        installed_bytes = target.read_bytes()
        self.assertTrue(installed_bytes.startswith(original))
        self.assertNotIn(b"devflow policy", installed_bytes)
        self.assertIn(b"operates only in the checkout where it is invoked", installed_bytes)
        self.assertIn(b"worktree lifecycle action", installed_bytes)
        self.assertIn(b"devflow --json review", installed_bytes)
        self.assertIn(b"hunk session review <session-id> --include-patch --include-notes --json", installed_bytes)
        self.assertIn(b"hunk session comment add <session-id>", installed_bytes)
        self.assertIn(b"ordinary `git commit`", installed_bytes)
        self.assertIn(b"ordinary merge of current mainline into WIP", installed_bytes)
        self.assertEqual(target.stat().st_mode & 0o777, 0o640)

        repeated = self.devflow("--json", "harness", "install", "codex")
        self.assertEqual(repeated.returncode, 0, repeated.stderr)
        self.assertFalse(json_output(repeated)["changed"])
        self.assertEqual(target.read_bytes(), installed_bytes)
        status = self.devflow("--json", "harness", "status", "codex")
        self.assertEqual(json_output(status)["status"], "installed")

        removed = self.devflow("--json", "harness", "remove", "codex")
        self.assertEqual(removed.returncode, 0, removed.stderr)
        self.assertEqual(target.read_bytes(), original)
        self.assertEqual(target.stat().st_mode & 0o777, 0o640)

    def test_outdated_owned_block_can_be_upgraded_or_removed_without_changing_outside_bytes(self) -> None:
        codex_target = Path(self.env["CODEX_HOME"]) / "AGENTS.md"
        codex_target.parent.mkdir()
        prefix = b"# User-owned prefix\nNo final newline here"
        suffix = b"# User-owned suffix\x00with exact bytes"
        outdated = (
            b"\n<!-- dotfiles-devflow:begin v1 -->\n"
            b"Old guidance that is still structurally owned.\n"
            b"<!-- dotfiles-devflow:end v1 -->\n"
        )
        codex_target.write_bytes(prefix + outdated + suffix)
        codex_target.chmod(0o604)

        status = self.devflow("--json", "harness", "status", "codex")
        self.assertEqual(status.returncode, 0, status.stderr)
        self.assertEqual(json_output(status)["status"], "outdated")
        self.assertFalse(json_output(status)["changed"])

        upgraded = self.devflow("--json", "harness", "install", "codex")
        self.assertEqual(upgraded.returncode, 0, upgraded.stderr)
        self.assertEqual(json_output(upgraded)["status"], "installed")
        self.assertTrue(json_output(upgraded)["changed"])
        upgraded_bytes = codex_target.read_bytes()
        self.assertTrue(upgraded_bytes.startswith(prefix))
        self.assertTrue(upgraded_bytes.endswith(suffix))
        self.assertNotIn(b"Old guidance", upgraded_bytes)
        self.assertIn(b"devflow --json review", upgraded_bytes)
        self.assertEqual(codex_target.stat().st_mode & 0o777, 0o604)

        codex_target.write_bytes(prefix + outdated + suffix)
        codex_target.chmod(0o604)
        removed = self.devflow("--json", "harness", "remove", "codex")
        self.assertEqual(removed.returncode, 0, removed.stderr)
        self.assertEqual(json_output(removed)["status"], "absent")
        self.assertTrue(json_output(removed)["changed"])
        self.assertEqual(codex_target.read_bytes(), prefix + suffix)
        self.assertEqual(codex_target.stat().st_mode & 0o777, 0o604)

    def test_malformed_owned_blocks_fail_closed_for_every_action(self) -> None:
        target = Path(self.env["CODEX_HOME"]) / "AGENTS.md"
        target.parent.mkdir()
        begin = b"<!-- dotfiles-devflow:begin v1 -->"
        end = b"<!-- dotfiles-devflow:end v1 -->"
        current_shape = b"\n" + begin + b"\nbody\n" + end + b"\n"
        malformed_cases = {
            "duplicate": current_shape + current_shape,
            "incomplete": b"\n" + begin + b"\nbody\n",
            "reversed": b"\n" + end + b"\nbody\n" + begin + b"\n",
            "unknown-version": (b"\n<!-- dotfiles-devflow:begin v2 -->\nbody\n<!-- dotfiles-devflow:end v2 -->\n"),
            "stray-token": b"User prose containing dotfiles-devflow:begin without an owned block.",
            "damaged-framing": begin + b"\nbody\n" + end + b"\n",
        }
        for case, malformed in malformed_cases.items():
            for action in ("status", "install", "remove"):
                with self.subTest(case=case, action=action):
                    target.write_bytes(malformed)
                    target.chmod(0o620)
                    refused = self.devflow("--json", "harness", action, "codex")
                    self.assertEqual(refused.returncode, 2)
                    self.assertEqual(json_output(refused)["error"]["code"], "harness_block_malformed")
                    self.assertEqual(target.read_bytes(), malformed)
                    self.assertEqual(target.stat().st_mode & 0o777, 0o620)

    def test_unsafe_target_fails_closed(self) -> None:
        codex_target = Path(self.env["CODEX_HOME"]) / "AGENTS.md"
        codex_target.parent.mkdir()

        claude_dir = self.home / ".claude"
        claude_dir.mkdir()
        real = self.root / "real-guidance"
        real.write_text("user owned")
        (claude_dir / "CLAUDE.md").symlink_to(real)
        unsafe = self.devflow("--json", "harness", "status", "claude")
        self.assertEqual(unsafe.returncode, 2)
        self.assertEqual(json_output(unsafe)["error"]["code"], "harness_target_unsafe")

        relative = run(
            [str(DEVFLOW), "--json", "harness", "install", "codex"],
            cwd=self.root,
            env={"HOME": str(self.home), "CODEX_HOME": "relative/codex"},
        )
        self.assertEqual(relative.returncode, 2)
        self.assertEqual(json_output(relative)["error"]["code"], "harness_root_unsafe")

        empty = run(
            [str(DEVFLOW), "--json", "harness", "install", "codex"],
            cwd=self.root,
            env={"HOME": str(self.home), "CODEX_HOME": ""},
        )
        self.assertEqual(empty.returncode, 2)
        self.assertEqual(json_output(empty)["error"]["code"], "harness_root_unsafe")


if __name__ == "__main__":
    unittest.main()
