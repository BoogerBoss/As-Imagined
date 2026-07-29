#!/usr/bin/env python3
r"""[M36A] Battle-anim script extractor: battle_anim_scripts.s -> scripts.json.

Scope of record: docs/m26_f1_recon.md (M36A = Phase A1 of the approved tiered
port). This converts the reference's 35,606-line animation bytecode source into
one JSON program the Godot AnimScriptVM (M36B) executes directly.

Step-0 findings this implementation rests on (all re-verified against the tree
at generation time rather than trusted from the recon):

- `data/battle_anim_scripts.s` contains ONLY: `#include`/`.include`/`.section`
  preamble, `@` comments, labels (`Name:` / `Name::`), and macro invocations.
  Zero raw `.byte/.2byte/.4byte/.align` directives outside macro bodies
  (verified by grep at authoring time; the parser errors loudly on any line it
  cannot classify, so drift shows up as a failure, not silent data loss).
- Labels ALIAS freely (gBattleAnimMove_None:: / _MirrorMove:: / _Pound:: share
  one body) and scripts share non-exported subroutines via `call`/`goto`
  (FlamethrowerCreateFlames et al). The faithful model is therefore ONE global
  command array plus a label->index map — exactly how the GBA sees it (the VM
  jumps to a pointer; ours jumps to an index). No per-script nesting exists.
- The opcode macros in `asm/macros/battle_anim_script.inc` are recognized by
  NAME + SIGNATURE (parsed from the `.macro` line); their `.byte` bodies are
  encoding detail we deliberately do not reproduce — the JSON stores structured
  commands, not bytes. Convenience macros (the ~70 `create_*_sprite` wrappers,
  `simple_palette_blend`, `jumpret*`, ...) are TEXTUALLY EXPANDED with GAS
  semantics: positional-then-keyword arg binding, parameter defaults, `\param`
  substitution, then whole-expression integer evaluation. That ordering is
  load-bearing: call sites write `y_velocity=80/256` and macro bodies write
  `256 * \y_velocity`, so evaluation must happen AFTER substitution
  (`256 * 80/256` == 80 left-to-right), exactly as the assembler does it.
- A handful of macro bodies use `.if/.ifb/.ifnb/.else/.endif` (arg-presence
  and constant-expression branches — shake_mon_or_platform, launch_status_anim
  family). The expander implements those four directives plus `.error`
  (raises) and `.warning` (ignored). Nothing else appears.
- Every non-pointer argument is resolved to the INTEGER the assembler would
  have emitted, via the same C headers the .s file #includes (constants
  resolved transitively; `RGB(r,g,b)` implemented natively as r|g<<5|b<<10).
  Pointer arguments stay SYMBOLIC: sprite templates / task funcs (C symbols)
  and jump targets (labels). Division: C truncates toward zero and Python
  floors, which differ only for mixed-sign operands with a remainder. Every
  division in the tree today is either same-sign or exact (19 distinct
  mixed-sign expressions, all exact), so the extracted values are correct —
  and `_assert_c_division_safe` enforces that property on every evaluation
  rather than trusting it, so a future reference change cannot shift an
  offset by one silently.
- Move binding: expansion has NO gBattleAnims_Moves table; the pointer lives on
  the move struct (`.battleAnimScript` in src/data/moves_info.h, keyed by the
  `enum Move` in include/constants/moves.h). We join those into a numeric
  move-id -> label map, which matches this project's own move ids (the
  data/moves/move_%04d.tres convention). The general/status/special dispatch
  tables are parsed from src/battle_anim.c into name -> {id,label} maps.
- SE/pan args are resolved to ints like everything else and kept in place as
  structured no-ops per Rob's amended decision 3 (2026-07-29): the future
  M36-S audio pass reads them from this JSON with zero re-extraction.

Output: data/battle_anims/scripts.json
  { meta, commands: [[op, ...fields], ...], labels: {name: index},
    exports: [names], moves: {"id": label}, general/status/special tables,
    constants: {used-symbol: value} }
Command shapes mirror the opcode macro signatures verbatim and are emitted in
meta.opcode_signatures (self-describing; the VM binds by that order). Variadic
argv is always the final field, as a list.

Idempotent; overwrites unconditionally; prints per-table counts and totals.
"""

import ast
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ref_path import REF, PROJECT, assert_inside_project

SCRIPTS_S = os.path.join(REF, "data", "battle_anim_scripts.s")
MACROS_INC = os.path.join(REF, "asm", "macros", "battle_anim_script.inc")
MOVES_INFO = os.path.join(REF, "src", "data", "moves_info.h")
MOVES_ENUM = os.path.join(REF, "include", "constants", "moves.h")
BATTLE_ANIM_C = os.path.join(REF, "src", "battle_anim.c")

CONST_HEADERS = [
    os.path.join(REF, "include", "config", "general.h"),
    os.path.join(REF, "include", "config", "battle.h"),
    os.path.join(REF, "include", "constants", "battle_anim.h"),
    os.path.join(REF, "include", "constants", "rgb.h"),
    os.path.join(REF, "include", "constants", "songs.h"),
    os.path.join(REF, "include", "constants", "sound.h"),
    os.path.join(REF, "include", "constants", "battle.h"),
    os.path.join(REF, "include", "constants", "pokemon.h"),
    os.path.join(REF, "include", "constants", "battle_anim_scripts.h"),
    os.path.join(REF, "include", "constants", "battle_string_ids.h"),
    os.path.join(REF, "include", "constants", "items.h"),
    os.path.join(REF, "include", "gba", "io_reg.h"),
]

OUT_DIR = assert_inside_project(
    os.path.join(PROJECT, "data", "battle_anims"), "battle_anims data dir")
OUT_PATH = os.path.join(OUT_DIR, "scripts.json")


# ---------------------------------------------------------------------------
# Constant resolution (the C headers the .s file #includes)
# ---------------------------------------------------------------------------

_DEFINE_RE = re.compile(r"^\s*#define\s+(\w+)\s+(.+?)\s*(?://.*)?$")


def load_defines(paths):
    # ANIM_BATTLER: used by the upstream Tera scripts yet DEFINED NOWHERE in
    # the reference tree. It assembles only because createsprite's encoder
    # never emits the battler symbol as data — it is used solely in
    # `.if \anim_battler == ANIM_TARGET`, and GAS symbol-identity comparison
    # makes an undefined symbol compare unequal to ANIM_TARGET. Net semantic:
    # attacker-side subpriority basis. We bake that (= ANIM_ATTACKER = 0)
    # rather than carry an unresolvable string; Tera content is excluded from
    # this project regardless.
    defs = {"TRUE": "1", "FALSE": "0", "NULL": "0", "ANIM_BATTLER": "0"}
    for path in paths:
        with open(path) as f:
            text = f.read()
        for line in text.splitlines():
            line = line.split("//")[0]
            m = _DEFINE_RE.match(line)
            if not m:
                continue
            name, expr = m.group(1), m.group(2)
            if "(" in name:  # function-like macro definitions: skip
                continue
            # Strip block comments inside the expression.
            expr = re.sub(r"/\*.*?\*/", " ", expr).strip()
            if name not in defs:  # first definition wins (config defaults)
                defs[name] = expr
        # C enums (named or anonymous) — SHAKE_BG_X/SHAKE_MON_*, AnimBattler,
        # etc. live in enums, not #defines. Entries are stored as expressions
        # so explicit values may reference other constants; implicit entries
        # chain off the previous name, resolved lazily like everything else.
        clean = re.sub(r"//[^\n]*", "", text)
        clean = re.sub(r"/\*.*?\*/", " ", clean, flags=re.S)
        for em in re.finditer(r"\benum\b[^{;]*\{([^}]*)\}", clean, flags=re.S):
            prev_name = None
            for entry in em.group(1).split(","):
                entry = entry.strip()
                if not entry:
                    continue
                ee = re.match(r"^(\w+)\s*(?:=\s*(.+))?$", entry, flags=re.S)
                if not ee:
                    continue
                name = ee.group(1)
                if ee.group(2) is not None:
                    expr = ee.group(2).strip()
                elif prev_name is None:
                    expr = "0"
                else:
                    expr = "(%s) + 1" % prev_name
                if name not in defs:
                    defs[name] = expr
                prev_name = name
    return defs


class ConstResolver:
    """Resolves C constant expressions to ints, transitively and memoized."""

    def __init__(self, defines):
        self.defines = dict(defines)
        self.cache = {}
        self.used = {}

    def value(self, name):
        if name in self.cache:
            return self.cache[name]
        if name not in self.defines:
            raise KeyError(name)
        self.cache[name] = None  # cycle guard
        val = eval_expr(self.defines[name], self)
        self.cache[name] = val
        self.used[name] = val
        return val


_TOKEN_FIXES = [
    (re.compile(r"&&"), " and "),
    (re.compile(r"\|\|"), " or "),
    (re.compile(r"!(?!=)"), " not "),
]


def _assert_c_division_safe(expr, resolver):
    """Fail loudly if an expression divides with mixed-sign operands and a
    remainder.

    C truncates toward zero; Python floors. They agree on exact division and
    on same-sign operands, and every division in the current reference tree
    falls in that safe set (19 distinct mixed-sign expressions, all exact --
    e.g. `256 * -819 / 256`). But that is a property of today's data, not a
    guarantee: a future reference update introducing an inexact negative
    division would otherwise shift an animation offset by one pixel with
    nothing to notice it. So the property is checked rather than assumed.
    """
    if "/" not in expr and "%" not in expr:
        return
    try:
        tree = ast.parse(expr.replace("&&", " and ").replace("||", " or "),
                         mode="eval")
    except SyntaxError:
        return  # not parseable as Python; the main eval path reports it
    for node in ast.walk(tree):
        if not isinstance(node, ast.BinOp):
            continue
        if not isinstance(node.op, (ast.Div, ast.FloorDiv, ast.Mod)):
            continue
        try:
            a = eval_expr(ast.unparse(node.left), resolver)
            b = eval_expr(ast.unparse(node.right), resolver)
        except Exception:
            continue
        if b != 0 and (a < 0) != (b < 0) and a % b != 0:
            raise AssertionError(
                "inexact mixed-sign division %r (%d / %d): C truncates to %d "
                "but Python floors to %d -- the extractor must be taught the "
                "C semantics before this data can be trusted"
                % (expr, a, b, int(a / b), a // b))


def eval_expr(expr, resolver):
    """Evaluate a C/GAS integer expression. Raises on unresolvable symbols."""
    s = expr.strip()
    # RGB(r,g,b) — implement the C macro natively (GBA 15-bit BGR).
    def rgb_repl(m):
        parts = split_args(m.group(1))
        r, g, b = (eval_expr(p, resolver) for p in parts)
        return str((r & 31) | ((g & 31) << 5) | ((b & 31) << 10))

    def rgb2gba_repl(m):
        parts = split_args(m.group(1))
        r, g, b = (eval_expr(p, resolver) for p in parts)
        return str(((r >> 3) & 31) | (((g >> 3) & 31) << 5)
                   | (((b >> 3) & 31) << 10))

    prev = None
    while prev != s:
        prev = s
        s = re.sub(r"\bRGB2GBA\s*\(([^()]*)\)", rgb2gba_repl, s)
        s = re.sub(r"\bRGB\s*\(([^()]*)\)", rgb_repl, s)
    for pat, rep in _TOKEN_FIXES:
        s = pat.sub(rep, s)
    s = s.replace("/", "@DIV@").replace("%", "@MOD@")
    s = s.replace("@DIV@", "//").replace("@MOD@", "%")

    names = set(re.findall(r"\b[A-Za-z_]\w*\b", s)) - {"and", "or", "not"}
    env = {}
    for n in names:
        env[n] = resolver.value(n)  # KeyError propagates to caller

    _assert_c_division_safe(s, resolver)
    val = eval(s, {"__builtins__": {}}, env)
    if isinstance(val, bool):
        val = int(val)
    if not isinstance(val, int):
        raise ValueError("non-integer result for %r -> %r" % (expr, val))
    return val


def split_args(text):
    """Split a comma-separated list, respecting parentheses (for C args)."""
    parts, depth, cur = [], 0, []
    for ch in text:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        if ch == "," and depth == 0:
            parts.append("".join(cur).strip())
            cur = []
        else:
            cur.append(ch)
    tail = "".join(cur).strip()
    if tail:
        parts.append(tail)
    return parts


_OPERATOR_CHARS = set("+-*/%|&^<>=~")


def split_invocation_args(text):
    r"""Split GAS macro-invocation arguments.

    GAS separates macro args by commas OR whitespace. But an expression like
    `256 * 80` (spaces around an operator, produced by macro-body arithmetic
    such as `256 * \x_velocity`) is ONE argument — the assembler continues an
    argument across whitespace when the boundary is operator-adjacent. Both
    styles genuinely occur in battle_anim_scripts.s (`SOUND_PAN_TARGET 10 3`
    is three args; `256 * 80` is one), so this splitter tokenizes on
    depth-0 commas/spaces and then re-merges SPACE-separated tokens whose
    boundary touches an operator character on either side. A comma boundary
    is never merge-eligible, even with trailing spaces (`foo, -3` stays two
    args — the leading `-` there is a sign, not a continuation).
    """
    tokens = []  # (text, separator_before: None | ',' | ' ')
    depth, cur = 0, []
    sep_pending = None
    for ch in text:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        if depth == 0 and ch == ",":
            if cur:
                tokens.append(("".join(cur), sep_pending))
                cur = []
            sep_pending = ","
        elif depth == 0 and ch in " \t":
            if cur:
                tokens.append(("".join(cur), sep_pending))
                cur = []
                sep_pending = " "
            elif sep_pending != "," and tokens:
                sep_pending = " "
        else:
            cur.append(ch)
    if cur:
        tokens.append(("".join(cur), sep_pending))
    merged = []
    for tok, sep in tokens:
        if merged and sep == " " and (
                merged[-1][-1] in _OPERATOR_CHARS or tok[0] in _OPERATOR_CHARS):
            merged[-1] = merged[-1] + tok
        else:
            merged.append(tok)
    return merged


# ---------------------------------------------------------------------------
# Macro definitions from battle_anim_script.inc
# ---------------------------------------------------------------------------

class MacroDef:
    def __init__(self, name, params, body):
        self.name = name
        self.params = params  # list of (name, default_or_None, is_vararg)
        self.body = body      # list of raw body lines (opcode macros: unused)
        self.is_opcode = bool(body) and body[0].lstrip().startswith(".byte 0x")


_MACRO_RE = re.compile(r"^\s*\.macro\s+(\w+)\s*(.*)$")


def parse_macros(path):
    macros = {}
    with open(path) as f:
        lines = f.readlines()
    i = 0
    while i < len(lines):
        m = _MACRO_RE.match(lines[i].split("@")[0])
        if not m:
            i += 1
            continue
        name, paramtext = m.group(1), m.group(2).strip()
        params = []
        if paramtext:
            for p in split_args(paramtext):
                is_vararg = p.endswith(":vararg")
                p = p.replace(":vararg", "").replace(":req", "")
                if "=" in p:
                    pname, default = p.split("=", 1)
                    params.append((pname.strip(), default.strip(), is_vararg))
                else:
                    params.append((p.strip(), None, is_vararg))
        body = []
        i += 1
        while i < len(lines) and not lines[i].lstrip().startswith(".endm"):
            raw = lines[i].split("@")[0].rstrip()
            if raw.strip():
                body.append(raw.strip())
            i += 1
        macros[name] = MacroDef(name, params, body)
        i += 1
    return macros


def bind_args(macro, args):
    """GAS binding: positional args fill parameters in declaration order
    (overriding defaults); name=value binds by name and moves the positional
    cursor past it. The vararg parameter soaks all remaining positionals."""
    defaults = {p: d for p, d, _v in macro.params if d is not None}
    vararg_name = next((p for p, _d, v in macro.params if v), None)
    order = [p for p, _d, _v in macro.params]
    bound = {}
    varargs = []
    pos_idx = 0
    for a in args:
        km = re.match(r"^(\w+)\s*=\s*(.*)$", a)
        if km and km.group(1) in order and km.group(1) != vararg_name:
            bound[km.group(1)] = km.group(2).strip()
            pos_idx = order.index(km.group(1)) + 1
            continue
        if pos_idx < len(order) and order[pos_idx] != vararg_name:
            bound[order[pos_idx]] = a
            pos_idx += 1
        else:
            varargs.append(a)
    for p, d in defaults.items():
        bound.setdefault(p, d)
    if vararg_name is not None:
        bound[vararg_name] = varargs
    return bound


_SUBST_RE = re.compile(r"\\(\w+)")


def substitute(line, bound, param_names):
    def repl(m):
        name = m.group(1)
        if name in bound:
            v = bound[name]
            if isinstance(v, list):
                return ", ".join(v)
            return v
        if name in param_names:
            return ""  # optional parameter left blank at the call site
        return m.group(0)
    return _SUBST_RE.sub(repl, line)


# ---------------------------------------------------------------------------
# The extractor
# ---------------------------------------------------------------------------

POINTER_OPS = {
    # op -> indices (by signature position) that are symbols/labels, kept as-is
    "createsprite": [0], "createvisualtask": [0], "createsoundtask": [0],
    "createvisualtaskontargets": [0], "createspriteontargets": [0],
    "createspriteontargets_onpos": [0],
    "call": [0], "goto": [0], "choosetwoturnanim": [0, 1],
    "jumpifmoveturn": [1], "jumpargeq": [2], "jumpifcontest": [0],
    "jumpifmovetypeequal": [1],
}


class Extractor:
    def __init__(self):
        self.macros = parse_macros(MACROS_INC)
        self.resolver = ConstResolver(load_defines(CONST_HEADERS))
        self.commands = []
        self.labels = {}
        self.exports = []
        self.unresolved = {}

    def arg_value(self, op, idx, text):
        text = text.strip()
        if op in POINTER_OPS and idx in POINTER_OPS[op]:
            return text
        try:
            return eval_expr(text, self.resolver)
        except (KeyError, SyntaxError, NameError, ValueError):
            self.unresolved.setdefault(text, 0)
            self.unresolved[text] += 1
            return text

    def emit(self, op, args):
        macro = self.macros[op]
        fields = []
        flat_idx = 0
        bound = bind_args(macro, args)
        for pname, _default, is_vararg in macro.params:
            if is_vararg:
                argv = bound.get(pname, [])
                fields.append([self.arg_value(op, flat_idx + k, a)
                               for k, a in enumerate(argv)])
            else:
                if pname not in bound:
                    raise ValueError("missing arg %s for %s" % (pname, op))
                fields.append(self.arg_value(op, flat_idx, bound[pname]))
                flat_idx += 1
        self.commands.append([op] + fields)

    def expand(self, name, args, depth=0):
        if depth > 8:
            raise RecursionError("macro depth exceeded at %s" % name)
        macro = self.macros.get(name)
        if macro is None:
            raise ValueError("unknown macro invocation: %s" % name)
        if macro.is_opcode:
            self.emit(name, args)
            return
        bound = bind_args(macro, args)
        param_names = {p[0] for p in macro.params}
        # conditional-aware body walk
        stack = [True]  # active-branch stack
        taken = [True]
        for raw in macro.body:
            line = substitute(raw, bound, param_names).strip()
            if line.startswith(".if") or line.startswith(".else") or \
               line.startswith(".endif") or line.startswith(".error") or \
               line.startswith(".warning"):
                if line.startswith(".ifb"):
                    arg = line[len(".ifb"):].strip()
                    cond = (arg == "")
                    stack.append(stack[-1] and cond)
                    taken.append(cond)
                elif line.startswith(".ifnb"):
                    arg = line[len(".ifnb"):].strip()
                    cond = (arg != "")
                    stack.append(stack[-1] and cond)
                    taken.append(cond)
                elif line.startswith(".if"):
                    expr = line[len(".if"):].strip()
                    cond = bool(eval_expr(expr, self.resolver)) if stack[-1] \
                        else False
                    stack.append(stack[-1] and cond)
                    taken.append(cond)
                elif line.startswith(".else"):
                    prev = taken[-1]
                    stack[-1] = stack[-2] and not prev
                elif line.startswith(".endif"):
                    stack.pop()
                    taken.pop()
                elif line.startswith(".error"):
                    if stack[-1]:
                        raise ValueError("macro .error reached in %s" % name)
                # .warning: ignore
                continue
            if not stack[-1]:
                continue
            im = re.match(r"^(\w+)\s*(.*)$", line)
            self.expand(im.group(1), split_invocation_args(im.group(2))
                        if im.group(2) else [], depth + 1)

    def run(self):
        cond_stack = [True]
        cond_taken = [True]
        with open(SCRIPTS_S) as f:
            for lineno, raw in enumerate(f, 1):
                line = raw.split("@")[0].strip()
                # GAS treats ';' as a statement separator, and upstream has a
                # stray one (`goto ParabolicChargeHeal;`, scripts.s:7284). It
                # is never part of a symbol, so drop it before parsing.
                line = line.rstrip(";").strip()
                if not line:
                    continue
                if line.startswith("#") or line.startswith(".include") or \
                   line.startswith(".section"):
                    continue
                if line.startswith(".if"):
                    cond = bool(eval_expr(line[3:].strip(), self.resolver)) \
                        if cond_stack[-1] else False
                    cond_stack.append(cond_stack[-1] and cond)
                    cond_taken.append(cond)
                    continue
                if line.startswith(".else"):
                    cond_stack[-1] = cond_stack[-2] and not cond_taken[-1]
                    continue
                if line.startswith(".endif"):
                    cond_stack.pop()
                    cond_taken.pop()
                    continue
                if not cond_stack[-1]:
                    continue
                lm = re.match(r"^(\w+)(::?)\s*(.*)$", line)
                if lm and lm.group(2):
                    name = lm.group(1)
                    self.labels[name] = len(self.commands)
                    if lm.group(2) == "::":
                        self.exports.append(name)
                    rest = lm.group(3).strip()
                    if rest:
                        im = re.match(r"^(\w+)\s*(.*)$", rest)
                        self.expand(im.group(1),
                                    split_invocation_args(im.group(2))
                                    if im.group(2) else [])
                    continue
                im = re.match(r"^(\w+)\s*(.*)$", line)
                if not im:
                    raise ValueError("line %d unparseable: %r" % (lineno, raw))
                try:
                    self.expand(im.group(1),
                                split_invocation_args(im.group(2))
                                if im.group(2) else [])
                except Exception as e:
                    raise ValueError("line %d (%s): %s" % (lineno, line, e))


# ---------------------------------------------------------------------------
# C-side tables
# ---------------------------------------------------------------------------

def parse_move_enum():
    """include/constants/moves.h: `enum __attribute__((packed)) Move`.
    Entries may alias earlier ones (MOVE_DOUBLESLAP = MOVE_DOUBLE_SLAP)."""
    ids = {}
    cur = -1
    in_enum = False
    with open(MOVES_ENUM) as f:
        for line in f:
            if not in_enum and re.search(r"\benum\b.*\bMove\b", line):
                in_enum = True
                continue
            if not in_enum:
                continue
            if line.strip().startswith("}"):
                break
            m = re.match(r"\s*([A-Za-z_]\w*)\s*(?:=\s*(\w+))?\s*,", line)
            if m:
                if m.group(2) is not None:
                    val = m.group(2)
                    cur = ids[val] if val in ids else int(val, 0)
                else:
                    cur += 1
                ids[m.group(1)] = cur
    return ids


def parse_move_bindings(move_ids):
    moves = {}
    cur_move = None
    with open(MOVES_INFO) as f:
        for line in f:
            mm = re.match(r"\s*\[(MOVE_\w+)\]\s*=", line)
            if mm:
                cur_move = mm.group(1)
                continue
            bm = re.search(r"\.battleAnimScript\s*=\s*(\w+)", line)
            if bm and cur_move is not None:
                if cur_move in move_ids:
                    moves[str(move_ids[cur_move])] = bm.group(1)
                cur_move = None
    return moves


def parse_dispatch_table(source, table_name):
    entries = {}
    m = re.search(re.escape(table_name) + r"\s*\[", source)
    if not m:
        raise SystemExit("dispatch table %s not found" % table_name)
    idx = 0
    for line in source[m.end():].splitlines():
        if line.strip().startswith("};"):
            break
        em = re.match(r"\s*\[(\w+)\]\s*=\s*(\w+)\s*,", line)
        if em:
            entries[em.group(1)] = {"index": idx, "label": em.group(2)}
            idx += 1
    return entries


def main():
    ex = Extractor()
    ex.run()

    move_ids = parse_move_enum()
    moves = parse_move_bindings(move_ids)

    with open(BATTLE_ANIM_C) as f:
        anim_c = f.read()
    status = parse_dispatch_table(anim_c, "sBattleAnims_StatusConditions")
    general = parse_dispatch_table(anim_c, "sBattleAnims_General")
    special = parse_dispatch_table(anim_c, "sBattleAnims_Special")

    # Cross-checks: every referenced label/table entry must exist.
    missing = [l for l in set(moves.values()) if l not in ex.labels]
    for tab in (status, general, special):
        missing += [e["label"] for e in tab.values()
                    if e["label"] not in ex.labels]
    if missing:
        raise SystemExit("labels referenced but not defined: %s"
                         % sorted(set(missing))[:10])
    if ex.unresolved:
        raise SystemExit("unresolved symbols in args: %s"
                         % sorted(ex.unresolved.items())[:20])

    opcode_signatures = {
        name: [p[0] + ("..." if p[2] else "") for p in m.params]
        for name, m in ex.macros.items() if m.is_opcode
    }

    prefix_counts = {}
    for name in ex.exports:
        pfx = name.split("_")[0] + "_" + (name.split("_")[1][:7]
                                          if "_" in name else "")
        prefix_counts[pfx] = prefix_counts.get(pfx, 0) + 1

    out = {
        "meta": {
            "generated_by": "scripts/gen_battle_anim_scripts.py [M36A]",
            "source": "data/battle_anim_scripts.s",
            "command_count": len(ex.commands),
            "label_count": len(ex.labels),
            "export_count": len(ex.exports),
            "move_binding_count": len(moves),
            "opcode_signatures": opcode_signatures,
        },
        "commands": ex.commands,
        "labels": ex.labels,
        "exports": ex.exports,
        "moves": moves,
        "general": general,
        "status": status,
        "special": special,
        "constants": dict(sorted(ex.resolver.used.items())),
    }

    os.makedirs(OUT_DIR, exist_ok=True)
    with open(OUT_PATH, "w") as f:
        json.dump(out, f, separators=(",", ":"))
    size_kb = os.path.getsize(OUT_PATH) // 1024
    print("commands: %d  labels: %d  exports: %d" %
          (len(ex.commands), len(ex.labels), len(ex.exports)))
    print("moves bound: %d  general: %d  status: %d  special: %d" %
          (len(moves), len(general), len(status), len(special)))
    exported_moves = sum(1 for n in ex.exports
                         if n.startswith("gBattleAnimMove_"))
    print("gBattleAnimMove_ exports: %d (recon expects 941)" % exported_moves)
    print("wrote %s (%d KB)" % (os.path.relpath(OUT_PATH, PROJECT), size_kb))


if __name__ == "__main__":
    main()
