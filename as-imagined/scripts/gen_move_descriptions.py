#!/usr/bin/env python3
"""
[M26E4-1] Patches real in-game move descriptions into gen_moves.py's own
MOVES dict entries -- the one blocking data gap the recon (docs/m26_e4_
recon.md §2.2) found for the Summary screen's MOVES-page detail panel.

Source: reference/pokeemerald_expansion/src/data/moves_info.h, each move's
own `.description = COMPOUND_STRING("...")` field -- the real, compact
two-line GBA move-description text (confirmed the ONLY description form
used there; no move references a shared/external description string).
Deliberately NOT data/moves.json (that pipeline has zero real consumers,
per the M19-pipeline-fix note in CLAUDE.md's own status history) and
deliberately NOT a hand-expanded prose rewrite the way AbilityData's own
descriptions were authored per-ability across many M17 sessions -- 717
moves at that scale is a bulk-extraction job, not a curation one, and the
real GBA text is exactly what source's own Summary-screen move-detail panel
shows.

Extraction, not transcription: moves_info.h's own move structs contain
NESTED curly braces elsewhere (.contestComboMoves = {COMBO_STARTER_POUND}),
so each move's own block boundary is found by brace-counting from its
`[MOVE_XXX] = {` opener, not a naive non-greedy regex -- a fragile shortcut
that would silently mis-bound around the first nested `}` it met.

A REAL, CONFIRMED WRINKLE, not assumed away: 37 of the 717 implemented
moves' own `.description` value is not one flat run of adjacent string
literals -- it's gated by inline `#if COND / #elif / #else / #endif`
preprocessor blocks selecting between generation-dependent wordings
(Disable's own 3-way turn-count text is the widest example), and a further
9 embed a bare `BINDING_TURNS` macro token (itself `#if`-gated) between two
quoted fragments rather than inside one. A first-draft version of this
script used a plain regex assuming one contiguous run of quoted literals
and silently produced ZERO description for exactly these 37 -- caught by
comparing the extracted count (896) against the per-entry patch report (37
of 717 unresolved) before trusting the output. Fixed with a small
line-by-line `#if` evaluator (see `_eval_condition`/`_resolve_description_
literal` below) rather than widening the regex further, since a regex
cannot express nested branch-taking.

Every condition is resolved against this project's own real, already-
established assumptions -- NOT "guess whichever reads better":
  - `MACRO >= GEN_N` / `MACRO != GEN_1` -> TRUE, matching this project's
    standing "assume GEN_LATEST" convention (confirmed directly: every
    `B_*` macro touched here except one really does default to GEN_LATEST
    in include/config/battle.h).
  - `MACRO == GEN_N` (an exact, non-latest generation) -> FALSE, since
    GEN_LATEST (GEN_9) is never equal to an earlier single generation.
  - `B_USE_FROSTBITE == TRUE` -> FALSE. Confirmed directly:
    `#define B_USE_FROSTBITE FALSE` in include/config/battle.h, and
    move_data.gd's own doc comment already confirms no STATUS_FROSTBITE
    exists anywhere in this codebase -- so every Frostbite-gated
    description correctly falls through to its own real #else wording
    ("...may freeze it." etc.), matching this project's actual Freeze-only
    status implementation.
  - The bare `BINDING_TURNS` macro (itself gated on `B_BINDING_TURNS >=
    GEN_5`, also GEN_LATEST by default) resolves to its own real "4 or 5"
    text, matching this project's own already-shipped binding-move
    duration roll ([M18.5f]: "a random 4-5 turns").

Idempotent: patching gen_moves.py checks each entry for an existing
"description" key first and skips it, so a rerun after a manual edit is
safe and a rerun with no source changes is a no-op.

Usage (from project root):
    python3 scripts/gen_move_descriptions.py
    python3 scripts/gen_moves.py   # regenerate the 717 .tres files after
"""
import json
import os
import re

from ref_path import REF

SCRIPTS_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPTS_DIR)

MOVES_INFO_SRC = os.path.join(REF, "src", "data", "moves_info.h")
MOVE_NAME_MAP = os.path.join(PROJECT_ROOT, "data", "move_name_to_id.json")
GEN_MOVES_PY = os.path.join(SCRIPTS_DIR, "gen_moves.py")

BLOCK_START_RE = re.compile(r"\[(MOVE_[A-Z0-9_]+)\]\s*=\s*\n?\s*\{")
DESCRIPTION_LINE_RE = re.compile(r"\.description\s*=\s*COMPOUND_STRING\(")
FIELD_LINE_RE = re.compile(r"^\.[A-Za-z_]\w*\s*=")

# Real per-macro resolved values, each confirmed directly against
# include/config/battle.h's own real `#define` (not assumed uniform) --
# everything else touched by these 37 conditional descriptions defaults to
# GEN_LATEST, this project's own standing convention. `B_ICE_WEATHER_*`
# aren't GEN comparisons at all -- they're a 3-way symbolic toggle
# (`B_PREFERRED_ICE_WEATHER` defaults to `B_ICE_WEATHER_BOTH`, matching
# this project's own already-decided Hail/Snow collapse, `[D2 batch]`'s
# CLAUDE.md entry) -- self-mapped so a bare occurrence on either side of a
# comparison resolves to its own real symbol rather than falling through to
# the GEN_LATEST default.
MACRO_VALUES = {
    "B_USE_FROSTBITE": "FALSE",
    "B_PREFERRED_ICE_WEATHER": "B_ICE_WEATHER_BOTH",
    "B_ICE_WEATHER_BOTH": "B_ICE_WEATHER_BOTH",
    "B_ICE_WEATHER_HAIL": "B_ICE_WEATHER_HAIL",
    "B_ICE_WEATHER_SNOW": "B_ICE_WEATHER_SNOW",
}
_GEN_LATEST_TOKEN = "GEN_LATEST"

# BINDING_TURNS is itself a `#define` gated on `B_BINDING_TURNS >= GEN_5`
# (moves_info.h's own preamble, lines ~12-16) -- GEN_LATEST by default, so
# resolves to its real "4 or 5" text, matching this project's own already-
# shipped binding-move duration roll ([M18.5f]).
BARE_MACROS = {"BINDING_TURNS": "4 or 5"}

_GEN_RE = re.compile(r"^GEN_(\d+)$")
_LATEST_ORDINAL = 9  # GEN_LATEST == GEN_9 in this reference checkout.


def _resolve_macro(name: str) -> str:
    """A comparable token: a GEN_N string, TRUE/FALSE, a project-specific
    symbol (B_ICE_WEATHER_*), or the GEN_LATEST default for anything not
    explicitly listed above."""
    if name in ("TRUE", "FALSE") or _GEN_RE.match(name):
        return name
    return MACRO_VALUES.get(name, _GEN_LATEST_TOKEN)


def _eval_single_condition(cond: str) -> bool:
    m = re.match(r"^\s*([A-Z][A-Z0-9_]*)\s*(>=|<=|==|!=|>|<)\s*([A-Za-z0-9_]+)\s*$", cond)
    if not m:
        # Nothing this project's own move descriptions actually need falls
        # outside "MACRO OP RHS" -- fail loudly rather than silently
        # guessing, so an unexpected future shape gets noticed.
        raise ValueError("unparseable #if condition: %r" % cond)
    macro, op, rhs = m.groups()
    lhs = _resolve_macro(macro)
    rhs_resolved = _resolve_macro(rhs)

    lhs_is_gen = lhs == _GEN_LATEST_TOKEN or _GEN_RE.match(lhs)
    rhs_is_gen = rhs_resolved == _GEN_LATEST_TOKEN or _GEN_RE.match(rhs_resolved)
    if lhs_is_gen and rhs_is_gen:
        lhs_n = _LATEST_ORDINAL if lhs == _GEN_LATEST_TOKEN else int(_GEN_RE.match(lhs).group(1))
        rhs_n = _LATEST_ORDINAL if rhs_resolved == _GEN_LATEST_TOKEN else int(_GEN_RE.match(rhs_resolved).group(1))
        if op == ">=":
            return lhs_n >= rhs_n
        if op == ">":
            return lhs_n > rhs_n
        if op == "<=":
            return lhs_n <= rhs_n
        if op == "<":
            return lhs_n < rhs_n
        if op == "==":
            return lhs_n == rhs_n
        if op == "!=":
            return lhs_n != rhs_n
    # Direct symbolic equality (TRUE/FALSE, or a project-specific symbol
    # pair like B_ICE_WEATHER_BOTH).
    if op == "==":
        return lhs == rhs_resolved
    if op == "!=":
        return lhs != rhs_resolved
    raise ValueError("cannot order-compare non-GEN tokens: %r" % cond)


def _eval_condition(cond: str) -> bool:
    """Supports a single top-level `||` (Razor Wind's own
    `B_UPDATED_MOVE_DATA == GEN_3 || B_UPDATED_MOVE_DATA == GEN_1`) -- the
    only compound form any of the 37 real descriptions actually use,
    confirmed via direct source read rather than building a full C
    expression parser for a case that doesn't occur."""
    if "||" in cond:
        return any(_eval_single_condition(part) for part in cond.split("||"))
    if "&&" in cond:
        return all(_eval_single_condition(part) for part in cond.split("&&"))
    return _eval_single_condition(cond)


def _decode_c_string(raw: str) -> str:
    # [Real, confirmed wrinkle] Source's own fixed-width GBA line wrap
    # sometimes splits mid-WORD at a real hyphen (Tackle's own
    # "a full-\nbody tackle." -- one hyphenated wrap, not two separate
    # words), confirmed via direct pixel/text inspection against 7 real
    # cases this project's own moves actually hit (Tackle, Bullet Punch,
    # Karate Chop, Headbutt, Water/Fire Pledge, Freeze-Dry). Collapsing
    # every `\n` to a bare space would leave a stray space after the
    # hyphen ("full- body"). A trailing hyphen immediately before the
    # escaped newline is the wrap-continuation signal -- resolved with no
    # inserted space -- while every other `\n` genuinely separates two
    # words and gets one.
    return (raw.replace("-\\n", "-")
               .replace("\\n", " ")
               .replace('\\"', '"')
               .replace("\\\\", "\\"))


_QUOTED_OR_BARE_RE = re.compile(
    r'"((?:[^"\\]|\\.)*)"'          # a quoted segment
    r'|([A-Z][A-Z0-9_]*)'          # or a bare macro identifier
)


def _extract_line_text(line: str) -> str:
    """A content line may hold one or more quoted fragments interleaved
    with a bare macro token (e.g. `"for "BINDING_TURNS" turns."`) -- walk
    it left to right rather than assuming one shape or the other."""
    out = []
    for m in _QUOTED_OR_BARE_RE.finditer(line):
        quoted, bare = m.groups()
        if quoted is not None:
            out.append(_decode_c_string(quoted))
        elif bare in BARE_MACROS:
            out.append(BARE_MACROS[bare])
        # An unrecognized bare identifier (shouldn't occur given the 37
        # confirmed cases) is silently skipped rather than guessed at.
    return "".join(out)


def _find_block_end(text: str, open_brace_idx: int) -> int:
    """Brace-count from an opening `{` to its true matching `}` (index of
    the character AFTER the closing brace) -- handles the real nested
    .contestComboMoves = {...} braces inside a move struct correctly."""
    depth = 0
    i = open_brace_idx
    while i < len(text):
        c = text[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    raise ValueError("unbalanced braces starting at %d" % open_brace_idx)


def _extract_move_description(block: str) -> str:
    """`block` is a whole move struct's body (from its opening `{` on).
    ONE single preprocessor-aware pass over the ENTIRE struct, not just a
    span bounded around `.description` -- because the real conditional
    shape isn't uniform:

      - Disable/Ice-Beam-style: the #if/#else lives INSIDE the
        `COMPOUND_STRING(...)` parens, selecting a fragment of the string.
      - Hail/Aurora-Veil/Razor-Wind-style: the #if/#else wraps the WHOLE
        `.description = COMPOUND_STRING(...)` STATEMENT -- two (or three)
        complete, independently-closed alternatives, confirmed directly
        (Hail's own Snow/Hail wording swap; Tri Attack nests BOTH shapes
        at once, an outer whole-statement #if with an inner Frostbite #if).

    A single shared #if/#elif/#else/#endif stack, walked once over the
    whole struct, handles every depth/shape uniformly: whichever branch is
    "active" when a `.description = COMPOUND_STRING(` line is reached is
    the one whose content gets captured; the walk naturally stops the
    instant a genuine field boundary (`.effect = `, etc.) is reached while
    the stack is back to empty -- which is also what makes an outer-wrapped
    field resolve correctly without ever needing to paren-match (the SECOND,
    inactive `.description = COMPOUND_STRING(` occurrence, inside the
    branch NOT taken, is walked right past without being mistaken for the
    end of the field, since the stack isn't empty there yet)."""
    stack = []  # each: [parent_active, any_taken_this_chain, currently_taking]

    def _active() -> bool:
        return stack[-1][2] if stack else True

    found_description = False
    out_parts = []

    for raw_line in block.splitlines():
        line = raw_line.strip()
        if not line:
            continue

        if line.startswith("#if"):
            parent_active = _active()
            taken = parent_active and _eval_condition(line[3:].strip())
            stack.append([parent_active, taken, taken])
            continue
        if line.startswith("#elif"):
            parent_active, any_taken, _ = stack[-1]
            if any_taken:
                stack[-1][2] = False
            else:
                taken = parent_active and _eval_condition(line[5:].strip())
                stack[-1] = [parent_active, taken, taken]
            continue
        if line.startswith("#else"):
            parent_active, any_taken, _ = stack[-1]
            stack[-1][2] = parent_active and not any_taken
            stack[-1][1] = True
            continue
        if line.startswith("#endif"):
            stack.pop()
            continue

        desc_match = DESCRIPTION_LINE_RE.search(line)
        if desc_match is not None:
            found_description = True
            line = line[desc_match.end():]
        elif found_description and not stack and FIELD_LINE_RE.match(line):
            # A genuine field boundary at top-level nesting -- the
            # unambiguous end signal for BOTH shapes described above,
            # reached only once every #if this field's own description
            # opened has been popped back to empty.
            break

        if found_description and _active():
            out_parts.append(_extract_line_text(line))

    joined = "".join(out_parts)
    return re.sub(r"\s+", " ", joined).strip()


def extract_descriptions() -> dict:
    """Returns {MOVE_XXX_CONSTANT_NAME: flowing description string}."""
    with open(MOVES_INFO_SRC, encoding="utf-8") as f:
        text = f.read()

    out = {}
    for m in BLOCK_START_RE.finditer(text):
        move_const = m.group(1)
        open_brace_idx = text.index("{", m.end() - 1)
        block_end = _find_block_end(text, open_brace_idx)
        block = text[open_brace_idx:block_end]

        resolved = _extract_move_description(block)
        if resolved:
            out[move_const] = resolved
    return out


def _escape_for_gdscript_and_python_literal(text: str) -> str:
    # Escaped once for embedding inside a Python double-quoted string
    # literal inside gen_moves.py's own MOVES dict -- render()'s own
    # GDScript-quoting escape (backslash/quote) runs later, at .tres
    # generation time, against whatever literal Python string value this
    # produces, so this only needs to be valid Python source.
    return text.replace("\\", "\\\\").replace('"', '\\"')


ENTRY_START_RE = re.compile(r'\{"id":\s*(\d+),\s*"name":\s*"([^"]*)",')


def patch_gen_moves(descriptions_by_id: dict) -> tuple:
    with open(GEN_MOVES_PY, encoding="utf-8") as f:
        content = f.read()

    moves_list_start = content.index("MOVES = [")
    moves_list_end = content.index("\n]\n", moves_list_start)

    out_parts = [content[:moves_list_start]]
    pos = moves_list_start
    patched = 0
    already_had = 0
    no_description_available = []

    matches = list(ENTRY_START_RE.finditer(content, moves_list_start, moves_list_end))
    for match in matches:
        out_parts.append(content[pos:match.end()])
        pos = match.end()

        move_id = int(match.group(1))
        entry_end = content.index("},", match.end()) + 2
        entry_body = content[match.end():entry_end]

        if '"description"' in entry_body:
            already_had += 1
            continue

        description = descriptions_by_id.get(move_id)
        if not description:
            no_description_available.append((move_id, match.group(2)))
            continue

        escaped = _escape_for_gdscript_and_python_literal(description)
        out_parts.append('\n     "description": "%s",' % escaped)
        patched += 1

    out_parts.append(content[pos:])
    new_content = "".join(out_parts)
    with open(GEN_MOVES_PY, "w", encoding="utf-8") as f:
        f.write(new_content)

    return patched, already_had, no_description_available


def main():
    with open(MOVE_NAME_MAP, encoding="utf-8") as f:
        name_to_id = json.load(f)

    by_const_name = extract_descriptions()
    print("Extracted %d move descriptions from moves_info.h" % len(by_const_name))

    descriptions_by_id = {}
    unresolved_names = 0
    for const_name, desc in by_const_name.items():
        move_id = name_to_id.get(const_name)
        if move_id is None:
            unresolved_names += 1
            continue
        # First occurrence per id wins (aliases share one real struct entry
        # under their canonical name; this project's own move_name_to_id.json
        # already resolves aliases to the SAME id, so a later alias-derived
        # duplicate would just be redundant, never conflicting).
        descriptions_by_id.setdefault(move_id, desc)

    patched, already_had, no_desc = patch_gen_moves(descriptions_by_id)
    print("gen_moves.py: %d entries patched, %d already had a description, "
          "%d have no reference description available (unresolved constant "
          "names: %d)" % (patched, already_had, len(no_desc), unresolved_names))
    if no_desc:
        print("  Moves with no description resolved:")
        for mid, name in no_desc:
            print("    %d %s" % (mid, name))


if __name__ == "__main__":
    main()
