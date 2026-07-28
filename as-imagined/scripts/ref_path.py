"""The canonical pokeemerald-expansion clone — defined once, imported everywhere.

Every generator under scripts/ reads the reference tree. Before this module they
each derived that path themselves, and six of them derived it *wrong*: an
expression like `os.path.join(ROOT, "reference", ...)` resolves to
`as-imagined/reference/`, the stale copy CLAUDE.md's own "Ground truth" table
marks do-not-use, rather than the canonical clone one level above the project.

That was a bug class, not a bug — the same slip in six places, each invisible
because the stale clone's *content* happens to be identical today. It will stop
being identical the moment the two diverge, and the failure would be silent
regeneration from four-day-old source.

So: one definition, and nothing derives its own.

    from ref_path import REF

Layout this assumes (verified at import):

    /home/rob/GodotAsImagined/          <- repo root
      reference/pokeemerald_expansion/  <- CANONICAL, what REF points at
      as-imagined/                      <- the Godot project
        reference/pokeemerald_expansion <- stale copy, deliberately NOT this
        scripts/ref_path.py             <- this file
"""

import os

_SCRIPTS = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(_SCRIPTS)
REPO_ROOT = os.path.dirname(PROJECT)

REF = os.path.join(REPO_ROOT, "reference", "pokeemerald_expansion")


def assert_inside_project(path, label):
    """Fail at import if a generated OUTPUT path escapes the project.

    The mirror of _verify() above, and for the same reason. _verify() guards
    the reference path against resolving into the wrong tree; this guards the
    output paths against the same class in the opposite direction.

    It exists because that class recurred: `gen_map_import.py` hardcoded
    absolute output paths into one specific checkout, so running it from a
    worktree silently wrote 421 map JSONs into the ORIGINAL tree and left the
    worktree empty. The reference-path sweep missed it precisely because these
    are outputs, not references.

    A future refactor that breaks the derivation now dies loudly here rather
    than writing hundreds of files into whatever tree sits at a stale path.
    """
    real = os.path.realpath(path)
    root = os.path.realpath(PROJECT)
    if real != root and not real.startswith(root + os.sep):
        raise SystemExit(
            "ref_path: %s resolves OUTSIDE the project (%s). Generated output "
            "must land inside %s -- derive it from PROJECT rather than "
            "hardcoding a path." % (label, real, root))
    return path


def _verify():
    if not os.path.isdir(REF):
        raise SystemExit(
            "ref_path: canonical reference clone not found at %s — see CLAUDE.md's "
            "'Ground truth / reference' table." % REF
        )
    # Guard against the exact mistake this module exists to prevent: a REF that
    # resolves INSIDE the Godot project is the stale copy, not the canonical one.
    if os.path.realpath(REF).startswith(os.path.realpath(PROJECT) + os.sep):
        raise SystemExit(
            "ref_path: REF resolved inside the Godot project (%s) — that is the "
            "stale do-not-use clone." % REF
        )


_verify()
