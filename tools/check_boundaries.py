#!/usr/bin/env python3
"""Enforces package import boundaries (docs/PIVOT_PLAN.md §4.3, docs/BUILD_PLAN.md P0).

The simulation must stay headless so the same code can run on a dedicated server. Each rule
lists the only imports a package may use; anything else (vendor:raylib, steam:, a client
package...) fails the check with file:line. Add a rule when a new package is created.

This catches direct imports. test.sh also inspects the linked server binary's symbols, which
catches anything pulled in transitively.

usage: python3 -I tools/check_boundaries.py [REPO_ROOT]
"""
import re
import sys
from pathlib import Path

RULES = {
    # package dir     allowed import prefixes / exact relative paths
    "src/sim":    ["core:", "base:", "cw:"],
    "src/server": ["core:", "base:", "cw:", "../sim"],
}

IMPORT = re.compile(r'^\s*import\s+(?:[A-Za-z_]\w*\s+)?"([^"]+)"', re.M)


def check(root: Path) -> list[str]:
    errors = []
    for pkg, allowed in RULES.items():
        d = root / pkg
        if not d.is_dir():
            errors.append(f"{pkg}: package directory missing (rule exists but package does not)")
            continue
        for f in sorted(d.glob("*.odin")):
            text = f.read_text()
            for m in IMPORT.finditer(text):
                path = m.group(1)
                if not any(path == a or (a.endswith(":") and path.startswith(a)) for a in allowed):
                    line = text.count("\n", 0, m.start()) + 1
                    errors.append(f'{f.relative_to(root)}:{line}: import "{path}" not allowed in {pkg} '
                                  f"(allowed: {', '.join(allowed)})")
    return errors


def main() -> int:
    root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent
    errors = check(root)
    for e in errors:
        print(f"[BOUNDARY] {e}", file=sys.stderr)
    if errors:
        print(f"[BOUNDARY] {len(errors)} violation(s)", file=sys.stderr)
        return 1
    print(f"[BOUNDARY] OK: {', '.join(RULES)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
