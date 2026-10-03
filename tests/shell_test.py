#!/usr/bin/env python3
"""Exercise shell startup with real interpreters and isolated HOME directories."""

import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile


REPO = Path(__file__).resolve().parents[1]
FISH = shutil.which("fish")
# Homebrew Zsh includes its site-functions in the default fpath; the system
# interpreter exposes missing completion setup when inheriting Fish's PATH.
ZSH = "/bin/zsh" if Path("/bin/zsh").is_file() else shutil.which("zsh")
BREW = shutil.which("brew")
assert FISH and ZSH and BREW, "shell tests require Fish, Zsh, and Homebrew"
brew_repository = subprocess.check_output([BREW, "--repository"], text=True).strip()
SHELLENV = Path(brew_repository) / "Library/Homebrew/cmd/shellenv.sh"
assert SHELLENV.is_file(), "cannot find Homebrew's shellenv implementation"


def executable(path, contents):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(contents)
    path.chmod(0o755)


def run(command, env, *, script=""):
    result = subprocess.run(
        command, env=env, input=script, text=True, capture_output=True, timeout=20
    )
    assert result.returncode == 0, (
        f"{command!r} exited {result.returncode}\n{result.stdout}\n{result.stderr}"
    )
    return result.stdout


def fixture(root, name):
    directory = root / name
    home = directory / "home"
    for item in (".config/fish", ".local/bin", ".local/share/dotfiles", ".cache/fish/generated_completions", "tmp"):
        (home / item).mkdir(parents=True)
    shutil.copy(REPO / "fish/config.fish", home / ".config/fish/config.fish")
    shutil.copy(REPO / "zsh/.zshrc", home / ".zshrc")
    for shell in ("fish", "zsh"):
        shutil.copy(
            REPO / f"templates/local.{shell}",
            home / f".local/share/dotfiles/local.{shell}",
        )
    prefix = directory / "brew"
    (prefix / "sbin").mkdir(parents=True)
    executable(
        prefix / "bin/brew",
        f"""#!/bin/bash
source {shlex.quote(str(SHELLENV))}
export HOMEBREW_PREFIX={shlex.quote(str(prefix))}
export HOMEBREW_CELLAR="$HOMEBREW_PREFIX/Cellar"
export HOMEBREW_REPOSITORY="$HOMEBREW_PREFIX"
export HOMEBREW_PATH="$PATH"
case "$1" in
    shellenv) homebrew-shellenv "$2" ;;
    --prefix) printf '%s\\n' "$HOMEBREW_PREFIX" ;;
    *) exit 1 ;;
esac
""",
    )
    for command in ("mise", "atuin"):
        executable(
            prefix / f"bin/{command}",
            f'#!/bin/sh\nprintf "{command} %s\\n" "$*" >> "$STARTUP_LOG"\n',
        )
    env = {
        "HOME": str(home),
        "PATH": f"{prefix}/bin:/usr/bin:/bin",
        "TERM": "dumb",
        "TMPDIR": str(home / "tmp"),
        "XDG_CONFIG_HOME": str(home / ".config"),
        "XDG_DATA_HOME": str(home / ".local/share"),
        "XDG_CACHE_HOME": str(home / ".cache"),
        "XDG_STATE_HOME": str(home / ".local/state"),
        "MISE_FISH_AUTO_ACTIVATE": "0",
        "STARTUP_LOG": str(directory / "startup.log"),
    }
    return directory, home, prefix, env


def startup_calls(env):
    path = Path(env["STARTUP_LOG"])
    return path.read_text().splitlines() if path.exists() else []


with tempfile.TemporaryDirectory(prefix="dotfiles-shell-test-") as temporary:
    root = Path(temporary).resolve()
    for runtime in ("mise", "venv"):
        for shell, binary in (("fish", FISH), ("zsh", ZSH)):
            directory, home, prefix, env = fixture(root, f"{runtime}-{shell}")
            runtime_bin = directory / runtime / "bin"
            for command in ("python3", "bun"):
                executable(runtime_bin / command, f"#!/bin/sh\necho {runtime}\n")
                executable(prefix / f"bin/{command}", "#!/bin/sh\necho brew\n")
                executable(home / f".bun/bin/{command}", "#!/bin/sh\necho optional\n")
            env["PATH"] = f"{runtime_bin}:{home}/.local/bin:{prefix}/bin:/usr/bin:/bin"
            if runtime == "venv":
                env["VIRTUAL_ENV"] = str(runtime_bin.parent)
            rc = home / (".config/fish/config.fish" if shell == "fish" else ".zshrc")
            command = f"source {shlex.quote(str(rc))}; python3; bun"
            options = ["--no-config", "-c"] if shell == "fish" else ["-df", "-c"]
            output = run([binary, *options, command], env)
            assert output.splitlines() == [runtime, runtime], output
            assert not startup_calls(env), "noninteractive shell activated interactive tools"
            if shell == "fish":
                output = run([binary, "--no-config", "-i", "-c", command], env)
                assert output.splitlines() == [runtime, runtime], output
                assert startup_calls(env) == ["mise activate fish", "mise completion fish", "atuin init fish"]
    print("PASS Fish and Zsh preserve inherited Mise and virtualenv command resolution")

    for shell, binary in (("fish", FISH), ("zsh", ZSH)):
        directory, home, prefix, env = fixture(root, f"discovery-{shell}")
        lookup = directory / "lookup"
        lookup.mkdir()
        (lookup / "brew").symlink_to(prefix / "bin/brew")
        env["PATH"] = f"{lookup}:/usr/bin:/bin"
        rc = home / (".config/fish/config.fish" if shell == "fish" else ".zshrc")
        command = f"source {shlex.quote(str(rc))}; command -v mise"
        options = ["--no-config", "-c"] if shell == "fish" else ["-df", "-c"]
        assert run([binary, *options, command], env).strip() == str(prefix / "bin/mise")
    print("PASS Homebrew discovery adds missing executable paths")

    directory, home, prefix, env = fixture(root, "zsh-overrides")
    (home / ".local/share/dotfiles/local.zsh").write_text(
        "PROMPT='MACHINE_PROMPT> '\n"
        "alias nvim-reset='echo machine-reset'\n"
        "git_prompt() { print MACHINE_BRANCH; }\n"
        'MACHINE_EDITORS="$EDITOR:$VISUAL:$GIT_EDITOR"\n'
        "(( MACHINE_LOCAL_LOADS += 1 ))\n"
    )
    output = run(
        [ZSH, "-d", "-i", "-c", 'print -r -- "$PROMPT"; alias nvim-reset; git_prompt; '
         'print -r -- "$MACHINE_EDITORS:$MACHINE_LOCAL_LOADS"'],
        env,
    )
    assert output.splitlines() == [
        "MACHINE_PROMPT> ", "nvim-reset='echo machine-reset'", "MACHINE_BRANCH", "nvim:nvim:nvim:1"
    ], output
    print("PASS Zsh preserves machine prompt, alias, and function overrides after one local source")

    for inherited_exports in (False, True):
        directory, home, prefix, env = fixture(root, f"zsh-completions-{inherited_exports}")
        completions = prefix / "share/zsh/site-functions"
        completions.mkdir(parents=True)
        (completions / "_dotfiles_brew_probe").write_text("#compdef dotfiles-brew-probe\n")
        env["PATH"] = f"{prefix}/bin:{prefix}/sbin:{home}/.local/bin:/usr/bin:/bin"
        if inherited_exports:
            env.update(
                HOMEBREW_PREFIX=str(prefix),
                HOMEBREW_CELLAR=str(prefix / "Cellar"),
                HOMEBREW_REPOSITORY=str(prefix),
            )
        assert not run([str(prefix / "bin/brew"), "shellenv", "zsh"], env), (
            "fixture must exercise Homebrew's Brew-first PATH no-op"
        )
        output = run(
            [ZSH, "-d", "-i", "-c", 'print -rl -- "${_comps[dotfiles-brew-probe]}" "$PATH"; '
             'print -rl -- $fpath'],
            env,
        ).splitlines()
        assert output[:2] == ["_dotfiles_brew_probe", env["PATH"]], output
        assert output[2:].count(str(completions)) == 1, output
    print("PASS Zsh registers Homebrew completions with Brew-first PATH, with and without exports")

    directory, home, prefix, env = fixture(root, "handoff")
    local_zsh = home / ".local/share/dotfiles/local.zsh"
    with local_zsh.open("a") as handle:
        handle.write('\nexport MACHINE_SETTING="preserved"\n')
    executable(
        prefix / "bin/fish",
        '#!/bin/sh\nprintf "HANDOFF=%s EDITOR=%s\\n" "$MACHINE_SETTING" "$EDITOR"\n',
    )
    assert "HANDOFF=preserved EDITOR=nvim" in run([ZSH, "-d", "-i"], env)
    assert not startup_calls(env), "Zsh initialized tools before handing off to Fish"
    assert not (home / ".zcompdump").exists(), "Zsh initialized discarded completion state"
    print("PASS Zsh handoff preserves machine exports and skips discarded activation")

    output = run([ZSH, "-d", "-i", "-c", 'printf "ZSH_COMMAND=%s\\n" "$ZSH_VERSION"'], env)
    assert "ZSH_COMMAND=" in output and "HANDOFF=" not in output
    assert startup_calls(env) == ["mise activate zsh", "mise completion zsh", "atuin init zsh"]
    assert (home / ".zcompdump").exists(), "explicit interactive Zsh lost completion setup"
    assert "HANDOFF=" not in run([ZSH, "-d", "-i", "-c", ""], env)
    print("PASS explicit interactive Zsh commands retain completion and tool activation")

    directory, home, prefix, env = fixture(root, "fallback")
    # Exclude system Fish installations while retaining utilities used by compinit.
    for command in ("cat", "chmod", "cut", "dirname", "mkdir", "mv", "rm", "sed", "uname"):
        target = shutil.which(command)
        if target:
            (prefix / f"bin/{command}").symlink_to(target)
    env["PATH"] = str(prefix / "bin")
    output = run([ZSH, "-d", "-i"], env, script='printf "ZSH_FALLBACK=%s\\n" "$ZSH_VERSION"\nexit\n')
    assert "ZSH_FALLBACK=" in output
    assert startup_calls(env) == ["mise activate zsh", "mise completion zsh", "atuin init zsh"]
    print("PASS Fish-unavailable Zsh fallback retains interactive activation")

    resources = os.environ.get("GHOSTTY_RESOURCES_DIR")
    integration = Path(resources or "/nonexistent") / "shell-integration/fish/vendor_conf.d/ghostty-shell-integration.fish"
    if integration.is_file():
        directory, home, prefix, env = fixture(root, "ghostty")
        env.update(
            GHOSTTY_RESOURCES_DIR=resources,
            GHOSTTY_SHELL_FEATURES="title,ssh-env,ssh-terminfo",
            TERM="xterm-ghostty",
        )
        probe = (
            'emit fish_prompt; functions -q ssh; or exit 1; '
            'source "$HOME/.config/fish/config.fish"; '
            'functions -q __ghostty_setup; and exit 1; printf "GHOSTTY_OK\\n"'
        )
        executable(
            prefix / "bin/fish",
            f"#!/bin/sh\nexec {shlex.quote(FISH)} -i -c {shlex.quote(probe)}\n",
        )
        direct = env | {
            "XDG_DATA_DIRS": str(Path(resources) / "shell-integration"),
            "GHOSTTY_SHELL_INTEGRATION_XDG_DIR": str(Path(resources) / "shell-integration"),
        }
        assert "GHOSTTY_OK" in run([str(prefix / "bin/fish")], direct)
        handoff = env | {
            "ZDOTDIR": str(Path(resources) / "shell-integration/zsh"),
            "GHOSTTY_ZSH_ZDOTDIR": str(home),
        }
        assert "GHOSTTY_OK" in run([ZSH, "-d", "-i"], handoff)
        print("PASS real Ghostty Fish integration survives direct injection, Zsh handoff, and rc reload")
    else:
        print("SKIP real Ghostty integration (GHOSTTY_RESOURCES_DIR is unavailable)")

print("shell regression checks passed")
