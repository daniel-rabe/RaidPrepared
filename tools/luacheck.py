"""Syntax-check every Lua file listed in the .toc, using LuaJIT via lupa."""
import io
import os
import sys

import lupa

lua = lupa.LuaRuntime()
loadstring = lua.eval("loadstring or load")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(ROOT)
toc = io.open("RaidPrepared.toc", encoding="utf-8").read()
files = [line.strip().replace("\\", "/")
         for line in toc.splitlines()
         if line.strip().endswith(".lua")]

bad = 0
for rel in files:
    if not os.path.exists(rel):
        print("MISSING  %s" % rel)
        bad += 1
        continue
    source = io.open(rel, encoding="utf-8").read()
    chunk, err = loadstring(source, "@" + rel), None
    if chunk is None:
        # loadstring returns nil, message - re-call to get the message
        result = lua.eval("function(s, n) local f, e = loadstring(s, n) return e end")(
            source, "@" + rel)
        print("SYNTAX   %s\n         %s" % (rel, result))
        bad += 1
    else:
        print("ok       %s" % rel)

print("\n%d file(s) with problems" % bad)
sys.exit(1 if bad else 0)
