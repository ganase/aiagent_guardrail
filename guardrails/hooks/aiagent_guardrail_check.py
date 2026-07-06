#!/usr/bin/env python3
"""AI Agent Guardrail Check - v0.2

Design:
  - Fail-closed: any exception in claude-hook mode returns exit 2.
  - Trust anchor: in claude-hook mode, config path is derived from __file__ only,
    never from AIAGENT_GUARDRAIL_HOME (user-writable).
  - 3-layer policy: deny (exit 2) / allow (exit 0 + JSON) / ask (exit 0 + JSON).
"""
from __future__ import annotations

import argparse
import csv
import datetime
import getpass
import hashlib
import io
import json
import os
import re
import shlex
import sys
from pathlib import Path
from typing import Any

# Force UTF-8 stdout/stderr (Windows default is system code page)
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
else:
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", line_buffering=True)
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding="utf-8", line_buffering=True)

# Trust anchor: always derived from this file's location
_SCRIPT_DIR = Path(__file__).resolve().parent
_GUARDRAILS_DIR = _SCRIPT_DIR.parent


# ── Config resolution ──────────────────────────────────────────────────────────

def _get_config_dir(mode: str) -> Path:
    """claude-hook mode: trust only __file__-relative path. CLI: allow env var fallback."""
    if mode == "claude-hook":
        return _GUARDRAILS_DIR / "config"
    home = os.environ.get("AIAGENT_GUARDRAIL_HOME")
    if home:
        return Path(home) / "config"
    return _GUARDRAILS_DIR / "config"


# ── JSON loading ───────────────────────────────────────────────────────────────

def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


# ── Levenshtein distance (stdlib only, for typosquat detection) ────────────────

def levenshtein(a: str, b: str) -> int:
    if a == b:
        return 0
    if len(a) < len(b):
        a, b = b, a
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a):
        curr = [i + 1]
        for j, cb in enumerate(b):
            curr.append(min(prev[j + 1] + 1, curr[j] + 1, prev[j] + (ca != cb)))
        prev = curr
    return prev[-1]


# ── Tamper detection ───────────────────────────────────────────────────────────

def verify_hashes(config_dir: Path) -> str | None:
    """Return error string on hash mismatch, None if ok. Missing file = ok (dev env)."""
    hash_file = config_dir / "installed_hashes.csv"
    if not hash_file.exists():
        return None

    targets = {
        "guardrail_policy.json": config_dir / "guardrail_policy.json",
        "package_allowlist.json": config_dir / "package_allowlist.json",
    }

    try:
        with open(hash_file, encoding="utf-8") as f:
            reader = csv.reader(f)
            next(reader, None)  # skip header
            stored: dict[str, str] = {}
            for row in reader:
                if len(row) >= 2:
                    # Strip quotes from path key (installer wraps with "")
                    key = row[0].strip().strip("\"'").replace("/", "\\")
                    stored[key] = row[1].strip()
    except Exception:
        return None  # Unreadable hash file: proceed with warning (not fatal)

    for name, file_path in targets.items():
        if not file_path.exists():
            continue
        rel = f"config\\{name}"
        expected = stored.get(rel) or stored.get(f"config/{name}")
        if expected is None:
            continue  # Not tracked yet
        actual = hashlib.sha256(file_path.read_bytes()).hexdigest().upper()
        if actual != expected.upper():
            return (
                f"設定ファイルの改ざんを検知しました: {rel}\n"
                f"実際のSHA256: {actual}\n"
                f"期待値: {expected}"
            )
    return None


# ── Hook JSON output (claude-hook mode, exit 0 only) ──────────────────────────

def _hook_json(decision: str, reason: str) -> str:
    return json.dumps(
        {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": decision,
                "permissionDecisionReason": reason,
            }
        },
        ensure_ascii=False,
    )


# ── Decision actions ───────────────────────────────────────────────────────────

def action_deny(message: str, mode: str) -> int:
    """Block: stderr message + exit 2 (claude-hook) or exit 1 (cli)."""
    print(message, file=sys.stderr)
    return 2 if mode == "claude-hook" else 1


def action_allow(message: str, mode: str) -> int:
    """Allow: claude-hook outputs JSON with permissionDecision=allow."""
    if mode == "claude-hook":
        print(_hook_json("allow", message))
    else:
        print(f"ALLOW: {message}")
    return 0


def action_ask(message: str, mode: str) -> int:
    """
    Escalate to human.
    claude-hook: exit 0 + JSON permissionDecision=ask.
    cli: interactive [y/N]. Non-TTY stdin = deny.
    """
    if mode == "claude-hook":
        print(_hook_json("ask", message))
        return 0
    if not sys.stdin.isatty():
        print(f"DENY (非対話環境のため自動拒否): {message}", file=sys.stderr)
        return 1
    print(f"\n[ガードレール] 確認が必要なコマンドを検知しました。\n{message}")
    try:
        ans = input("続行しますか？ [y/N]: ").strip().lower()
    except (EOFError, KeyboardInterrupt):
        return 1
    if ans == "y":
        return 0
    print("導入を中止しました。AIガバナンスチームまたは管理者に相談してください。", file=sys.stderr)
    return 1


# ── Logging (best-effort: never let failures affect policy decisions) ──────────

def log_decision(
    logs_dir: Path, user: str, ecosystem: str, package: str, decision: str, command: str
) -> None:
    try:
        logs_dir.mkdir(parents=True, exist_ok=True)
        log_file = logs_dir / "package_decisions.csv"
        write_header = not log_file.exists()
        with open(log_file, "a", encoding="utf-8", newline="") as f:
            writer = csv.writer(f)
            if write_header:
                writer.writerow(["timestamp", "user", "ecosystem", "package", "decision", "command"])
            writer.writerow([
                datetime.datetime.now(datetime.timezone.utc).isoformat(),
                user, ecosystem, package, decision,
                command[:500],
            ])
    except Exception:
        pass


# ── Name normalization ─────────────────────────────────────────────────────────

def normalize_name(name: str) -> str:
    return re.sub(r"[-_.]+", "-", name.strip().lower())


# ── Tokenization ───────────────────────────────────────────────────────────────

def tokenize(command: str) -> list[str]:
    try:
        return shlex.split(command, posix=False)
    except Exception:
        return command.split()


def is_option(token: str) -> bool:
    t = token.strip("\"'")
    return t.startswith("-") or t.startswith("/")


_PKG_NOISE = frozenset({
    "install", "i", "add", "ci", "remove", "uninstall",
    "pip", "pip3", "python", "python3", "py",
    "uv", "poetry", "conda",
    "npm", "yarn", "pnpm",
    "-m",
})


def clean_pkg_token(token: str) -> str | None:
    t = token.strip().strip("\"'")
    if not t or is_option(t):
        return None
    if t.lower() in _PKG_NOISE:
        return None
    name = re.split(r"[<>=!~;\[@ ]", t, maxsplit=1)[0].strip()
    if not name or name.lower() in _PKG_NOISE:
        return None
    return normalize_name(name)


# ── Requirements file parsing ──────────────────────────────────────────────────

def parse_requirements_file(path: Path) -> tuple[list[str], bool]:
    """
    Parse a requirements.txt file.
    Returns (package_names, has_custom_index).
    Raises on read error (caller treats as ask).
    """
    packages: list[str] = []
    has_custom_index = False

    lines = path.read_text(encoding="utf-8").splitlines()
    for line in lines:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if re.match(r"(-i\b|--index-url\b|--extra-index-url\b)", line, re.IGNORECASE):
            has_custom_index = True
            continue
        if line.startswith("-"):
            continue  # Other options (-r, -c, -f, etc.)
        if "://" in line or line.startswith("git+"):
            packages.append("__LOCAL_OR_VCS__" + line.split("#")[0].strip())
            continue
        if line.startswith((".", "/", "\\")):
            packages.append("__LOCAL_OR_VCS__" + line.split("#")[0].strip())
            continue
        # Normal package spec; strip environment marker
        name_part = line.split(";")[0].strip()
        name = re.split(r"[<>=!~\[\s]", name_part, maxsplit=1)[0].strip()
        if name:
            packages.append(normalize_name(name))

    return packages, has_custom_index


# ── package.json reading (npm/yarn/pnpm no-args install) ──────────────────────

def read_package_json_deps(cwd: Path | None = None) -> list[str] | None:
    """Return package names from package.json, or None if unreadable."""
    try:
        base = cwd if cwd is not None else Path.cwd()
        pj = base / "package.json"
        if not pj.exists():
            return None
        data = json.loads(pj.read_text(encoding="utf-8"))
        names: list[str] = []
        for section in ("dependencies", "devDependencies", "peerDependencies", "optionalDependencies"):
            names.extend(data.get(section, {}).keys())
        return [normalize_name(n) for n in names]
    except Exception:
        return None


# ── Allowlist lookup ───────────────────────────────────────────────────────────

def lookup_package(allowlist: dict[str, Any], ecosystem: str, name: str) -> dict[str, Any] | None:
    packages = allowlist.get("ecosystems", {}).get(ecosystem, {}).get("packages", [])
    norm = normalize_name(name)
    for pkg in packages:
        if normalize_name(pkg.get("name", "")) == norm:
            return pkg
    return None


def all_allow_names(allowlist: dict[str, Any], ecosystem: str) -> list[str]:
    packages = allowlist.get("ecosystems", {}).get(ecosystem, {}).get("packages", [])
    return [normalize_name(p.get("name", "")) for p in packages if p.get("status") == "allow"]


# ── Typosquatting detection ────────────────────────────────────────────────────

def check_typosquat(name: str, allowlist: dict[str, Any], ecosystem: str) -> str | None:
    """Return similar allow-list name if typosquat suspected, else None."""
    norm = normalize_name(name)
    for allowed in all_allow_names(allowlist, ecosystem):
        if allowed == norm:
            return None  # exact match – not a typosquat
        if 1 <= levenshtein(norm, allowed) <= 2:
            return allowed
    return None


# ── Package extraction ─────────────────────────────────────────────────────────

def extract_packages(
    command: str,
    ecosystem: str,
) -> tuple[list[str], bool, bool]:
    """
    Returns (packages, has_custom_index, is_no_args_install).
    Packages may include sentinel strings:
      __LOCAL_OR_VCS__<spec>  -> local path / VCS URL / wheel
      __REQFILE_NOT_FOUND__<path>
      __REQFILE_ERROR__<path>
    """
    tokens = tokenize(command)
    lower = [t.lower().strip("\"'") for t in tokens]

    has_custom_index = bool(re.search(r"--index-url|--extra-index-url", command, re.IGNORECASE))
    pkgs: list[str] = []

    if ecosystem == "python":
        install_idx = next((i for i, lt in enumerate(lower) if lt == "install"), None)
        if install_idx is None:
            return [], has_custom_index, False

        i = install_idx + 1
        while i < len(tokens):
            lt = lower[i]
            if lt in {"-r", "--requirement", "-c", "--constraint"}:
                if i + 1 < len(tokens):
                    req_path = Path(tokens[i + 1].strip("\"'"))
                    try:
                        file_pkgs, file_idx = parse_requirements_file(req_path)
                        pkgs.extend(file_pkgs)
                        if file_idx:
                            has_custom_index = True
                    except FileNotFoundError:
                        pkgs.append("__REQFILE_NOT_FOUND__" + str(req_path))
                    except Exception:
                        pkgs.append("__REQFILE_ERROR__" + str(req_path))
                    i += 2
                else:
                    i += 1
                continue
            if lt in {"--index-url", "--extra-index-url", "-i"}:
                has_custom_index = True
                i += 2
                continue
            if is_option(tokens[i]):
                i += 1
                continue
            t = tokens[i].strip("\"'")
            if "://" in t or t.startswith("git+"):
                pkgs.append("__LOCAL_OR_VCS__" + t)
            elif t.startswith((".", "..", "/", "\\")) or t.endswith((".whl", ".tar.gz", ".zip")):
                pkgs.append("__LOCAL_OR_VCS__" + t)
            else:
                pkg = clean_pkg_token(t)
                if pkg:
                    pkgs.append(pkg)
            i += 1
        return pkgs, has_custom_index, False

    elif ecosystem == "javascript":
        start = None
        for marker in ("install", "i", "add", "ci"):
            if marker in lower:
                start = lower.index(marker) + 1
                break
        if start is None:
            return [], False, False

        rest_non_option = [t for t in tokens[start:] if not is_option(t)]
        if not rest_non_option:
            return [], False, True  # no-args install -> caller reads package.json

        for t in rest_non_option:
            pkg = clean_pkg_token(t)
            if pkg:
                pkgs.append(pkg)
        return pkgs, False, False

    return [], False, False


# ── blocked_paths: Bash-based secret file access detection ────────────────────
# NOTE: python -c "open('.env')" or script-based access cannot be caught here.
# This is a known limitation documented in docs/既知の限界.md.

_READ_CMDS = frozenset({
    "cat", "type", "get-content", "gc", "more", "copy", "cp",
    "certutil", "select-string",
})

_BLOCKED_PATH_PATS = [
    re.compile(r"^\.env$", re.IGNORECASE),
    re.compile(r"^\.env\.", re.IGNORECASE),
    re.compile(r"(?:^|[/\\])secrets(?:[/\\]|$)", re.IGNORECASE),
    re.compile(r"\.pem$", re.IGNORECASE),
    re.compile(r"\.key$", re.IGNORECASE),
    re.compile(r"^id_rsa$", re.IGNORECASE),
    re.compile(r"^id_ed25519$", re.IGNORECASE),
]

_ENV_SAFE_RE = re.compile(r"\.(example|template|sample)$", re.IGNORECASE)


def _is_blocked_path(token: str) -> bool:
    t = token.strip().strip("\"'")
    if not t:
        return False
    norm = t.replace("\\", "/")
    basename = Path(norm).name

    for pat in _BLOCKED_PATH_PATS:
        if pat.search(basename) or pat.search(norm):
            if pat.pattern.startswith(r"^\.env") and _ENV_SAFE_RE.search(basename):
                return False
            return True
    return False


def check_blocked_paths(command: str) -> bool:
    """Return True if command reads a sensitive path (Bash-level check only)."""
    tokens = tokenize(command)
    if not tokens:
        return False

    has_read = any(
        Path(t.strip("\"'").replace("\\", "/")).name.lower() in _READ_CMDS
        or t.strip("\"'").lower() in _READ_CMDS
        for t in tokens
    )

    # curl -d @filepath / curl --data @filepath
    if re.search(r"\bcurl\b", command, re.IGNORECASE):
        for m in re.findall(r"@(\S+)", command):
            if _is_blocked_path(m):
                return True

    if not has_read:
        return False

    return any(_is_blocked_path(t) for t in tokens[1:])


# ── Per-package 3-layer evaluation ────────────────────────────────────────────

def evaluate_packages(
    pkgs: list[str],
    ecosystem: str,
    allowlist: dict[str, Any],
    policy: dict[str, Any],
    logs_dir: Path,
    user: str,
    command: str,
    mode: str,
) -> int:
    if not pkgs:
        reason = "パッケージ名を解析できませんでした。AIガバナンスチームまたは管理者に相談してください。"
        log_decision(logs_dir, user, ecosystem, "<unknown>", "ask", command)
        return action_ask(reason, mode)

    deny_reasons: list[str] = []
    ask_reasons: list[str] = []

    for pkg_name in pkgs:
        if pkg_name.startswith("__LOCAL_OR_VCS__"):
            actual = pkg_name[len("__LOCAL_OR_VCS__"):]
            ask_reasons.append(f"ローカルパス・VCS・wheel指定は人間の確認が必要です: {actual}")
            log_decision(logs_dir, user, ecosystem, actual, "ask", command)
            continue
        if pkg_name.startswith("__REQFILE_NOT_FOUND__"):
            actual = pkg_name[len("__REQFILE_NOT_FOUND__"):]
            ask_reasons.append(f"requirements ファイルが見つかりません: {actual}")
            log_decision(logs_dir, user, ecosystem, f"<reqfile:{actual}>", "ask", command)
            continue
        if pkg_name.startswith("__REQFILE_ERROR__"):
            actual = pkg_name[len("__REQFILE_ERROR__"):]
            ask_reasons.append(f"requirements ファイルが読み取れません: {actual}")
            log_decision(logs_dir, user, ecosystem, f"<reqfile:{actual}>", "ask", command)
            continue

        pkg_entry = lookup_package(allowlist, ecosystem, pkg_name)

        if pkg_entry is None:
            similar = check_typosquat(pkg_name, allowlist, ecosystem)
            if similar:
                deny_reasons.append(
                    f"タイポスクワッティングの可能性: '{pkg_name}' は許可済み '{similar}' に類似しています。\n"
                    f"正しいパッケージ名の場合はAIガバナンスチームまたは管理者に申請してください。"
                )
                log_decision(logs_dir, user, ecosystem, pkg_name, "deny(typosquat)", command)
            else:
                ask_reasons.append(
                    f"未審査パッケージ: {pkg_name}\n"
                    f"導入が必要な場合はAIガバナンスチームまたは管理者に申請してください。"
                )
                log_decision(logs_dir, user, ecosystem, pkg_name, "ask", command)
        else:
            status = pkg_entry.get("status", "")
            if status == "deny":
                deny_reasons.append(
                    policy["messages"]["package_not_allowed"]
                    + f"\necosystem={ecosystem}\npackage={pkg_name}\nreason={pkg_entry.get('reason')}"
                )
                log_decision(logs_dir, user, ecosystem, pkg_name, "deny", command)
            elif status == "review":
                ask_reasons.append(
                    policy["messages"]["package_review"]
                    + f"\necosystem={ecosystem}\npackage={pkg_name}\nreason={pkg_entry.get('reason')}"
                )
                log_decision(logs_dir, user, ecosystem, pkg_name, "ask(review)", command)
            else:  # allow
                log_decision(logs_dir, user, ecosystem, pkg_name, "allow", command)

    if deny_reasons:
        return action_deny("\n---\n".join(deny_reasons), mode)
    if ask_reasons:
        return action_ask("\n---\n".join(ask_reasons), mode)

    allowed_names = [p for p in pkgs if not p.startswith("__")]
    return action_allow(
        f"審査済みパッケージの導入を自動許可しました: {', '.join(allowed_names)}",
        mode,
    )


# ── Core check logic ───────────────────────────────────────────────────────────

def _check_command_impl(command: str, mode: str, config_dir: Path) -> int:
    if not command.strip():
        return action_allow("空コマンド", mode)

    policy = load_json(config_dir / "guardrail_policy.json")
    allowlist = load_json(config_dir / "package_allowlist.json")
    logs_dir = config_dir.parent / "logs"

    try:
        user = getpass.getuser()
    except Exception:
        user = "unknown"

    # C. Tamper detection (claude-hook only; mismatch = exit 2)
    if mode == "claude-hook":
        err = verify_hashes(config_dir)
        if err:
            return action_deny(f"[改ざん検知] {err}", mode)

    # 1. Dangerous command patterns (JSON-defined)
    for pat in policy.get("dangerous_command_patterns", []):
        if re.search(pat, command, re.IGNORECASE):
            return action_deny(
                policy["messages"]["dangerous_command"]
                + f"\npattern={pat}\ncommand={command}",
                mode,
            )

    # 2. Remove-Item: flag-order-independent check (code-level, not regex)
    if re.search(r"\bRemove-Item\b", command, re.IGNORECASE):
        # \b before - doesn't work (- is non-word char); match -Flag at any position
        if re.search(r"-Recurse\b", command, re.IGNORECASE) and re.search(
            r"-Force\b", command, re.IGNORECASE
        ):
            return action_deny(
                policy["messages"]["dangerous_command"]
                + f"\nRemove-Item with -Recurse and -Force (any order)\ncommand={command}",
                mode,
            )

    # 3. blocked_paths: Bash-based secret file read detection
    if check_blocked_paths(command):
        return action_deny(
            f"[blocked_path] 機密ファイルへのアクセスが検知されたためブロックしました。\n"
            f"command={command}\n"
            f"注意: python -c やスクリプト経由のアクセスは防げません（docs/既知の限界.md 参照）。",
            mode,
        )

    # 4. Runtime install patterns
    for pat in policy.get("runtime_install_patterns", []):
        if re.search(pat, command, re.IGNORECASE):
            return action_deny(
                policy["messages"]["runtime_install"]
                + f"\npattern={pat}\ncommand={command}",
                mode,
            )

    # 5. Package install patterns: 3-layer policy
    for ecosystem, patterns in policy.get("package_install_patterns", {}).items():
        if not any(re.search(p, command, re.IGNORECASE) for p in patterns):
            continue

        # External registry check (command-level, before file parsing)
        if re.search(r"--index-url|--extra-index-url", command, re.IGNORECASE):
            log_decision(logs_dir, user, ecosystem, "<external-registry>", "deny", command)
            return action_deny(
                f"[外部レジストリ] 社外PyPI/npmレジストリ指定は禁止されています。\ncommand={command}",
                mode,
            )

        pkgs, has_custom_index, is_no_args = extract_packages(command, ecosystem)

        if has_custom_index:
            log_decision(logs_dir, user, ecosystem, "<external-registry>", "deny", command)
            return action_deny(
                f"[外部レジストリ] requirements ファイル内に社外レジストリ指定が検出されました。\ncommand={command}",
                mode,
            )

        if is_no_args and ecosystem == "javascript":
            js_pkgs = read_package_json_deps()
            if js_pkgs is None:
                log_decision(logs_dir, user, ecosystem, "<package.json>", "ask", command)
                return action_ask("package.json が読み取れないため人間の承認が必要です。", mode)
            if not js_pkgs:
                return action_allow("package.json に依存パッケージがありません", mode)
            pkgs = js_pkgs

        return evaluate_packages(pkgs, ecosystem, allowlist, policy, logs_dir, user, command, mode)

    return action_allow("ガードレールチェック通過", mode)


def check_command(command: str, mode: str = "cli", config_dir: Path | None = None) -> int:
    """
    Fail-closed entry point.
    Any exception -> exit 2 (claude-hook) or exit 1 (cli).
    """
    resolved = config_dir if config_dir is not None else _get_config_dir(mode)
    try:
        return _check_command_impl(command, mode, resolved)
    except Exception as e:
        print(
            f"ガードレール内部エラーのため安全側で停止しました: {type(e).__name__}: {e}",
            file=sys.stderr,
        )
        return 2 if mode == "claude-hook" else 1


# ── stdin extraction ───────────────────────────────────────────────────────────

def extract_command_from_stdin() -> str:
    raw = sys.stdin.read()
    if not raw.strip():
        return ""
    try:
        payload = json.loads(raw)
    except Exception:
        return raw
    tool_input = payload.get("tool_input") or {}
    for key in ("command", "cmd", "script"):
        if isinstance(tool_input, dict) and isinstance(tool_input.get(key), str):
            return tool_input[key]
    return json.dumps(payload, ensure_ascii=False)


# ── Entry point ────────────────────────────────────────────────────────────────

def main() -> int:
    try:
        parser = argparse.ArgumentParser(description="AI Agent Guardrail Check v0.2")
        parser.add_argument("--mode", choices=["cli", "claude-hook"], default="cli")
        parser.add_argument("--command", help="Command string to check (or pass via stdin)")
        args = parser.parse_args()
        command = args.command if args.command is not None else extract_command_from_stdin()
        return check_command(command, args.mode)
    except SystemExit:
        raise
    except Exception as e:
        mode = "claude-hook" if "--mode" in sys.argv and "claude-hook" in sys.argv else "cli"
        print(
            f"ガードレール内部エラーのため安全側で停止しました: {type(e).__name__}: {e}",
            file=sys.stderr,
        )
        return 2 if mode == "claude-hook" else 1


if __name__ == "__main__":
    raise SystemExit(main())
