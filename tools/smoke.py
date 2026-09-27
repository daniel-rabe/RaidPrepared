"""Loads the whole addon against a stub of the WoW client and drives the dialog.

Build-time tool, not part of the shipped addon. It proves the code *runs* - that
every file loads in .toc order, that the window builds, that all six tabs select,
that the theme switch reaches every registered widget and that fun mode still
swaps its strings. It says nothing about how any of it looks, so it does not
replace loading the addon in the client.

The stub deliberately has no fallback for unknown widget methods: a method that
is missing raises instead of quietly returning nil, so a genuine mistake is not
swallowed. Unknown client *globals* do fall back to a string of their own name,
which is enough for the localized format strings the addon reads.

Needs lupa (a Lua runtime for Python):  pip install lupa

Usage:
    python tools/smoke.py
"""

import os
import sys

try:
    import lupa
except ImportError:
    raise SystemExit("smoke test needs lupa: pip install lupa")

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def main():
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    g = lua.globals()
    g.ROOT = ROOT.replace("\\", "/")
    g.SMOKE_DIR = os.path.join(HERE, "smoke").replace("\\", "/")
    g.TOC = os.path.join(ROOT, "RaidPrepared.toc").replace("\\", "/")

    try:
        lua.execute('dofile(SMOKE_DIR .. "/checks.lua")')
    except lupa.LuaError as err:
        print("SMOKE FAILED:\n%s" % err)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
