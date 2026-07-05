#!/usr/bin/env python3
from __future__ import annotations
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_ALLOWLIST = ROOT / "config" / "package_allowlist.json"

REQUIRED_TOP = {"schema_version", "allowlist_version", "updated_at", "owner", "description", "default_policy", "ecosystems"}
REQUIRED_PACKAGE = {"name", "status", "allowed_versions", "risk_level", "reason", "reviewed_by", "reviewed_at"}
VALID_STATUS = {"allow", "review", "deny"}
VALID_RISK = {"low", "medium", "high", "unknown"}


def error(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)


def validate(path: Path) -> list[str]:
    errors: list[str] = []
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        return [f"JSON読み込みに失敗しました: {exc}"]

    missing = REQUIRED_TOP - set(data)
    if missing:
        errors.append(f"トップレベル必須キー不足: {sorted(missing)}")
    if data.get("default_policy") != "deny":
        errors.append("default_policy は deny である必要があります")
    ecosystems = data.get("ecosystems")
    if not isinstance(ecosystems, dict):
        errors.append("ecosystems は object である必要があります")
        return errors
    for eco in ["python", "javascript"]:
        if eco not in ecosystems:
            errors.append(f"ecosystems.{eco} が存在しません")
            continue
        packages = ecosystems[eco].get("packages")
        if not isinstance(packages, list):
            errors.append(f"ecosystems.{eco}.packages は配列である必要があります")
            continue
        seen = set()
        for idx, pkg in enumerate(packages):
            prefix = f"ecosystems.{eco}.packages[{idx}]"
            if not isinstance(pkg, dict):
                errors.append(f"{prefix} は object である必要があります")
                continue
            missing_pkg = REQUIRED_PACKAGE - set(pkg)
            if missing_pkg:
                errors.append(f"{prefix} 必須キー不足: {sorted(missing_pkg)}")
            name = str(pkg.get("name", "")).strip().lower()
            if not name:
                errors.append(f"{prefix}.name が空です")
            if name in seen:
                errors.append(f"{prefix}.name が重複しています: {name}")
            seen.add(name)
            if pkg.get("status") not in VALID_STATUS:
                errors.append(f"{prefix}.status が不正です: {pkg.get('status')}")
            if pkg.get("risk_level") not in VALID_RISK:
                errors.append(f"{prefix}.risk_level が不正です: {pkg.get('risk_level')}")
    return errors


def main() -> int:
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_ALLOWLIST
    errors = validate(path)
    if errors:
        for e in errors:
            error(e)
        return 1
    print(f"OK: {path.name} is valid")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
