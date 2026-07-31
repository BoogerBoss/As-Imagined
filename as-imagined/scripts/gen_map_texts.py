#!/usr/bin/env python3
"""Extract every dialogue string from the reference tree into data/map_texts.json.

[M27F Stage 1] The scripts this project imports reference text by LABEL
(`msgbox PewterCity_Gym_Text_BrockIntro, MSGBOX_NPC`), and the text itself lives
beside the script in the same `scripts.inc` as a run of `.string` directives.

WHY EVERY LABEL, NOT JUST THE CORRIDOR'S: the corridor references 322, but which
maps are baked changes, and a per-bake text extraction would be the same
ordering hazard the trimmed-TileSet recon documents for tile definitions -- bake
a new map, silently have no text for it. Extracting the whole tree once removes
the question.

CONTROL CODES, which are the whole reason this is not a flat copy:
    \\n  newline WITHIN a message box
    \\l  scroll up one line (treated as a newline here -- this project's box is
        not line-limited the way the GBA's 2-line window is)
    \\p  PAGE BREAK: wait for a button, clear the box, continue
    $   string terminator

So one label is a LIST OF PAGES, each page a string with embedded newlines.
Measured on the corridor: 322 labels -> 1,004 `.string` lines -> 563 pages.

Output shape (data/map_texts.json):
    { "<Label>": ["page one\\nsecond line", "page two"], ... }

JSON rather than a generated .gd const dict (Rob's call): this is bulk CONTENT
rather than a lookup table, it is ~13x larger tree-wide than the corridor slice,
and a const dict that size parses on every load.
"""

import json
import os
import re
import sys

REF = "/home/rob/GodotAsImagined/reference/pokeemerald_expansion"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data", "map_texts.json")

# A label line, then a run of .string directives before the next label.
LABEL_RE = re.compile(r"^(\w+)::?\s*$", re.M)
STRING_RE = re.compile(r'^\s*\.string\s+"(.*)"\s*$')


def iter_inc_files():
    for root, _dirs, files in os.walk(os.path.join(REF, "data")):
        for f in files:
            if f.endswith(".inc") or f.endswith(".s"):
                yield os.path.join(root, f)


def pages_from_body(body):
    """Concatenate a label's .string run, then split it into message-box pages."""
    raw = []
    # Preprocessor state. 9 files tree-wide guard text with #ifdef, and the one
    # symbol used is BUGFIX, which is NOT defined in a normal build -- so the
    # branch that actually ships is the #else. Treating the directive as a
    # terminator (the first cut did) silently truncated those labels to nothing.
    skipping = False
    for line in body.splitlines():
        stripped = line.strip()
        if stripped.startswith("#"):
            directive = stripped.split()[0]
            if directive in ("#ifdef", "#if"):
                skipping = True          # guarded branch does not ship
            elif directive == "#ifndef":
                skipping = False         # this one DOES ship
            elif directive == "#else":
                skipping = not skipping
            elif directive == "#endif":
                skipping = False
            continue
        if skipping:
            continue
        m = STRING_RE.match(line)
        if m:
            raw.append(m.group(1))
        elif stripped and not stripped.startswith("@"):
            # A non-.string, non-comment line ends the text run. Text labels are
            # contiguous .string blocks; anything else means we ran into code.
            break
    if not raw:
        return None
    joined = "".join(raw)
    joined = joined.replace("\\$", "\x00")          # protect a literal $
    joined = joined.split("$")[0]                    # drop everything after the terminator
    joined = joined.replace("\x00", "$")
    pages = joined.split("\\p")
    out = []
    for p in pages:
        p = p.replace("\\l", "\\n")                  # scroll-line -> newline
        p = p.replace("\\n", "\n")
        # Real escaped quotes survive as-is; nothing else needs unescaping here.
        p = p.replace('\\"', '"')
        out.append(p.strip("\n"))
    return [p for p in out if p != ""] or [""]


def main():
    texts = {}
    collisions = 0
    for path in iter_inc_files():
        try:
            src = open(path, encoding="utf-8", errors="ignore").read()
        except OSError:
            continue
        marks = list(LABEL_RE.finditer(src))
        for i, m in enumerate(marks):
            name = m.group(1)
            start = m.end()
            end = marks[i + 1].start() if i + 1 < len(marks) else len(src)
            pages = pages_from_body(src[start:end])
            if pages is None:
                continue
            if name in texts and texts[name] != pages:
                # Same label defined twice with different content. Report rather
                # than silently keeping one -- the same discipline gen_map_import
                # applies to its own name->id tables.
                collisions += 1
                print("  COLLISION: %s defined twice with differing text" % name,
                      file=sys.stderr)
                continue
            texts[name] = pages

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(texts, f, ensure_ascii=False, indent=0, sort_keys=True)

    total_pages = sum(len(v) for v in texts.values())
    print("gen_map_texts: %d labels, %d pages -> %s"
          % (len(texts), total_pages, os.path.normpath(OUT)))
    if collisions:
        print("gen_map_texts: %d collisions reported above" % collisions)
    # An empty extraction must fail loudly, not write an empty file that every
    # later msgbox then silently renders as nothing.
    if not texts:
        print("gen_map_texts: FAILED - extracted zero labels", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
