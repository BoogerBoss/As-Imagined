#!/usr/bin/env python3
"""
[M27I I2] Generates data/std_strings.json: {"STDSTRING_ITEMS": "ITEMS", ...}.

`bufferstdstring STR_VAR_3, STDSTRING_ITEMS` copies a fixed string out of
source's `gStdStrings[]` into a text buffer, and the obtain-item flow uses it
for the POCKET name ("...put it in the {STR_VAR_3} POCKET."). 48 corpus uses,
16 of them in the corridor.

GENERATED rather than hand-typed for the same reason `metatile_behavior.gd`'s
240 constants are: 39 strings transcribed by hand is 39 chances to fumble one,
and the mistake would surface as one odd word inside a sentence rather than as
an error.

Two entry forms, both real in the table:
  * `[STDSTRING_ITEMS] = COMPOUND_STRING("ITEMS"),`   -- inline literal
  * `[STDSTRING_COOL]  = gText_Cool,`                 -- a reference, resolved
    out of src/strings.c

Anything that resolves to neither is reported rather than silently dropped, so
a future reference-tree change cannot quietly blank a string.
"""

import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(HERE)
REFERENCE = os.path.join(os.path.dirname(PROJECT), "reference", "pokeemerald_expansion")
TABLE = os.path.join(REFERENCE, "src", "data", "script_menu.h")
CONSTS = os.path.join(REFERENCE, "include", "constants", "script_menu.h")
STRINGS = os.path.join(REFERENCE, "src", "strings.c")
OUT = os.path.join(PROJECT, "data", "std_strings.json")

ROW = re.compile(r"\[(STDSTRING_[A-Z0-9_]+)\]\s*=\s*(.+?),\s*$", re.M)
COMPOUND = re.compile(r'COMPOUND_STRING\(\s*"((?:[^"\\]|\\.)*)"\s*\)')
GTEXT_DEF = re.compile(r'^const u8 (gText_[A-Za-z0-9_]+)\[\]\s*=\s*_\(\s*"((?:[^"\\]|\\.)*)"\s*\)', re.M)


def table_body(text):
    m = re.search(r"const u8 \*const gStdStrings\[\]\s*=\s*\{", text)
    if not m:
        sys.exit("gStdStrings[] not found")
    depth, out = 0, []
    for ch in text[m.end() - 1:]:
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                break
        out.append(ch)
    return "".join(out)


def main():
    body = table_body(open(TABLE, encoding="utf-8").read())
    gtext = dict(GTEXT_DEF.findall(open(STRINGS, encoding="utf-8").read()))

    out, unresolved = {}, []
    for name, expr in ROW.findall(body):
        expr = expr.strip()
        m = COMPOUND.search(expr)
        if m:
            out[name] = m.group(1)
            continue
        if expr in gtext:
            out[name] = gtext[expr]
            continue
        unresolved.append((name, expr))

    # The ordinals matter: `bufferstdstring` is given a NUMBER at runtime when
    # its argument came through a variable, so the map has to work both ways.
    const_text = open(CONSTS, encoding="utf-8").read()
    ordinals = {m.group(1): int(m.group(2)) for m in
                re.finditer(r"#define\s+(STDSTRING_[A-Z0-9_]+)\s+(\d+)", const_text)}
    missing_ord = sorted(set(out) - set(ordinals))
    if missing_ord:
        sys.exit("no ordinal for: %r" % missing_ord[:5])

    payload = {
        "by_name": dict(sorted(out.items())),
        "by_id": {str(ordinals[k]): v for k, v in sorted(out.items())},
    }
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(payload, f, indent="\t", sort_keys=True, ensure_ascii=False)
        f.write("\n")

    print("std strings : %s" % os.path.relpath(OUT, PROJECT))
    print("  resolved  : %d of %d constants" % (len(out), len(ordinals)))
    if unresolved:
        print("  UNRESOLVED: %d -> %s" % (len(unresolved), unresolved[:5]))


if __name__ == "__main__":
    main()
