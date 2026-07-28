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
