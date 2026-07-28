"""Canonical trainer keys — the ONE place the origin-suffix rule lives.

**Rule A** (see docs/overworld_scope.md): a trainer key is OUR identifier, and
every one carries a suffix naming the roster that defined it:

    TRAINER_ROXANNE_1   (src/data/trainers.party)       -> TRAINER_ROXANNE_1_RSE
    TRAINER_LASS_ROBIN  (src/data/trainers_frlg.party)  -> TRAINER_LASS_ROBIN_FRLG

The suffix is not decoration. The two rosters are separate files with separate
constants headers, and a key that does not say which one it came from is
ambiguous the moment both ship. The filename IS the key, so this also decides
where the .tres lands.

Deliberately distinct from **Rule B** (portrait stems), which are UPSTREAM's
identifiers copied verbatim and never suffixed by us — see that rule's own note
in the scope doc. The two rules differ because the identifiers have different
owners, not by oversight.

Both gen_trainer_data.py and gen_map_import.py import `canonical_key` from
here. The suffix rule must never be duplicated: two copies would drift, and a
drifted copy resolves a placement to a trainer that does not exist.
"""

import os
import re

from ref_path import REF

SUFFIX_RSE = "_RSE"
SUFFIX_FRLG = "_FRLG"

_HEADERS = {
    SUFFIX_RSE: os.path.join(REF, "include", "constants", "opponents.h"),
    SUFFIX_FRLG: os.path.join(REF, "include", "constants", "opponents_frlg.h"),
}

# Present in a header but not a trainer: the blank sentinel (excluded from both
# rosters, and the one name the two headers genuinely share) and the
# facility-partner macro.
_NOT_TRAINERS = {"TRAINER_NONE", "TRAINER_PARTNER"}

_index = None


def _build_index():
    """raw constant -> origin suffix, asserting the rosters stay disjoint."""
    global _index
    if _index is not None:
        return _index

    by_suffix = {}
    for suffix, path in _HEADERS.items():
        if not os.path.exists(path):
            raise SystemExit("trainer_keys: missing constants header %s" % path)
        with open(path, encoding="utf-8") as f:
            names = set(re.findall(r"\bTRAINER_[A-Z0-9_]+", f.read()))
        by_suffix[suffix] = names - _NOT_TRAINERS

    # Measured zero today. Asserted anyway: a future expansion update that
    # introduces a shared name would otherwise resolve it arbitrarily by dict
    # order, silently pointing placements at the wrong roster's trainer.
    overlap = by_suffix[SUFFIX_RSE] & by_suffix[SUFFIX_FRLG]
    if overlap:
        raise SystemExit(
            "trainer_keys: the two rosters are no longer disjoint — %d shared "
            "name(s), e.g. %s. The origin suffix cannot be derived from the "
            "constant alone; resolve this before regenerating."
            % (len(overlap), sorted(overlap)[:5])
        )

    idx = {}
    for suffix, names in by_suffix.items():
        for name in names:
            idx[name] = suffix
    _index = idx
    return idx


def canonical_key(raw):
    """Suffix a raw source constant with its roster of origin.

    Raises on anything unrecognised rather than guessing — an unknown constant
    means the headers and the caller disagree, which is worth failing on.
    """
    idx = _build_index()
    if raw in idx:
        return raw + idx[raw]
    if raw.endswith(SUFFIX_RSE) or raw.endswith(SUFFIX_FRLG):
        raise SystemExit(
            "trainer_keys: %r is already canonical; canonical_key() takes the "
            "RAW source constant." % raw
        )
    raise SystemExit(
        "trainer_keys: %r is not defined by either constants header." % raw
    )


def roster_counts():
    """(rse, frlg) real-trainer counts, for build-time reporting."""
    idx = _build_index()
    rse = sum(1 for s in idx.values() if s == SUFFIX_RSE)
    return rse, len(idx) - rse
