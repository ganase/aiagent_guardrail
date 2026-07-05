#!/usr/bin/env python3
from __future__ import annotations
import argparse
import json
import os
import re
import shlex
import subprocess
import sys
from pathlib import Path
from typing import Any

ROOT = Path(os.environ.get("AIAGENT_GUARDRAIL_HOME", Path(__file__).resolve().parents[1]))
CONFIG = ROOT / "config" / "guardrail_policy.json"
ALLOWLIST = ROOT / "config" / "package_allowlist.json"


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def normalize_name(name: str) -> str:
    return name.strip().lower().replace("_", "-")


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


def tokenize(command: str) -> list[str]:
    # Windows PowerShell文字列でも完全ではないが、パッケージ名抽出には十分な簡易解析。
    try:
        return shlex.split(command, posix=False)
    except Exception:
        return command.split()


def is_option(token: str) -> bool:
    return token.startswith("-") or token.startswith("/")


def clean_pkg_token(token: str) -> str | None:
    t = token.strip().strip('"\'')
    if not t or is_option(t):
        return None
    # requirements指定やローカルパスは個別レビュー扱い
    if t in {"install", "i", "add"}:
        return None
    if t.startswith((".", "..", "/", "\\")) or t.endswith((".whl", ".tar.gz", ".zip")):
        return t
    # pandas==2.0.0 / pandas>=2 のような指定から名前だけ抽出
    name = re.split(r"[<>=!~]", t, maxsplit=1)[0]
    if "@" in name and not name.startswith("@"):
        name = name.split("@", 1)[0]
    return normalize_name(name)


def extract_packages(command: str, ecosystem: str) -> list[str]:
    tokens = tokenize(command)
    lower = [t.lower().strip('"\'') for t in tokens]
    pkgs: list[str] = []
    if ecosystem == "python":
        # pip install x / python -m pip install x / py -m pip install x
        try:
            if "pip" in lower and "install" in lower:
                idx = lower.index("install")
                rest = tokens[idx + 1:]
            else:
                return []
        except ValueError:
            return []
        skip_next = False
        for t in rest:
            if skip_next:
                skip_next = False
                continue
            lt = t.lower().strip('"\'')
            if lt in {"-r", "--requirement", "-c", "--constraint", "--index-url", "--extra-index-url"}:
                # requirements経由は中身確認が必要なので、ファイル名を擬似パッケージとしてreview扱いにする
                skip_next = False
            pkg = clean_pkg_token(t)
            if pkg:
                pkgs.append(pkg)
    elif ecosystem == "javascript":
        start = None
        for marker in ["install", "i", "add"]:
            if marker in lower:
                start = lower.index(marker) + 1
                break
        if start is None:
            return []
        for t in tokens[start:]:
            pkg = clean_pkg_token(t)
            if pkg:
                pkgs.append(pkg)
    return pkgs


def lookup_package(allowlist: dict[str, Any], ecosystem: str, name: str) -> dict[str, Any] | None:
    packages = allowlist.get("ecosystems", {}).get(ecosystem, {}).get("packages", [])
    norm = normalize_name(name)
    for pkg in packages:
        if normalize_name(pkg.get("name", "")) == norm:
            return pkg
    return None


def deny(message: str, mode: str) -> int:
    print(message, file=sys.stderr)
    # Claude Code hooksでは exit code 2 がブロックの意味になる。
    return 2 if mode == "claude-hook" else 10


def allow(message: str | None = None) -> int:
    if message:
        print(message)
    return 0


def check_command(command: str, mode: str = "cli") -> int:
    if not command.strip():
        return allow("OK: empty command")
    policy = load_json(CONFIG)
    allowlist = load_json(ALLOWLIST)

    for pat in policy.get("dangerous_command_patterns", []):
        if re.search(pat, command, re.IGNORECASE):
            return deny(policy["messages"]["dangerous_command"] + f"\npattern={pat}\ncommand={command}", mode)

    for pat in policy.get("runtime_install_patterns", []):
        if re.search(pat, command, re.IGNORECASE):
            return deny(policy["messages"]["runtime_install"] + f"\npattern={pat}\ncommand={command}", mode)

    ecosystem_hit = []
    for ecosystem, patterns in policy.get("package_install_patterns", {}).items():
        if any(re.search(p, command, re.IGNORECASE) for p in patterns):
            ecosystem_hit.append(ecosystem)

    for ecosystem in ecosystem_hit:
        pkgs = extract_packages(command, ecosystem)
        if not pkgs:
            return deny(f"ライブラリ導入コマンドを検知しましたが、パッケージ名を解析できませんでした。AIガバナンスチームまたは管理者へ相談してください。\ncommand={command}", mode)
        for pkg_name in pkgs:
            pkg = lookup_package(allowlist, ecosystem, pkg_name)
            if pkg is None:
                return deny(policy["messages"]["package_not_allowed"] + f"\necosystem={ecosystem}\npackage={pkg_name}\ncommand={command}", mode)
            status = pkg.get("status")
            if status == "deny":
                return deny(policy["messages"]["package_not_allowed"] + f"\necosystem={ecosystem}\npackage={pkg_name}\nstatus=deny\nreason={pkg.get('reason')}", mode)
            if status == "review":
                return deny(policy["messages"]["package_review"] + f"\necosystem={ecosystem}\npackage={pkg_name}\nreason={pkg.get('reason')}", mode)
        return allow(f"OK: allowlisted package install command: {command}")

    return allow("OK: command passed guardrail check")


def main() -> int:
    parser = argparse.ArgumentParser(description="AI Agent guardrail check")
    parser.add_argument("--mode", choices=["cli", "claude-hook"], default="cli")
    parser.add_argument("--command", help="Command string to check")
    args = parser.parse_args()
    command = args.command if args.command is not None else extract_command_from_stdin()
    return check_command(command, args.mode)

if __name__ == "__main__":
    raise SystemExit(main())
