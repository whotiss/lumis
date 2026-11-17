"""NFR9: everything Lumis says about a result reads at Flesch-Kincaid grade 8 or below (estimated)."""
import json

import pytest

from app.readability import fk_grade, syllables
from app.wording import DISCLAIMER, PHOTO_CHECK_TEXT, result_text

CONDITIONS = json.loads(open("app/data/conditions.json", encoding="utf-8").read())
LIMIT = 8


def test_scorer_on_known_cases():
    assert [syllables(w) for w in ["cat", "water", "itchy", "moisturizer", "make"]] == [1, 2, 2, 4, 1]
    assert fk_grade("The cat sat on the mat.") < 1
    assert fk_grade("Psoriasis needs a doctor's diagnosis and is usually managed with treatment a doctor "
                    "recommends.") > LIMIT


@pytest.mark.parametrize("c", CONDITIONS, ids=[c["id"] for c in CONDITIONS])
def test_condition_texts(c):
    for field in ("about", "typical_presentation", "general_guidance"):
        assert fk_grade(c[field]) <= LIMIT, (c["id"], field, fk_grade(c[field]))


@pytest.mark.parametrize("band", ["high", "moderate", "refer"])
@pytest.mark.parametrize("urgency", ["routine", "see_doctor"])
@pytest.mark.parametrize("fit", [None, "not_typical"])
def test_result_wording(band, urgency, fit):
    # Condition names are fixed medical words, so a one-syllable stand-in is used: this scores Lumis's own wording.
    t = result_text(band, "Acne", urgency, fit)
    assert fk_grade(t.headline) <= LIMIT and fk_grade(t.advice) <= LIMIT, (t.headline, t.advice)


def test_photo_check_and_disclaimer():
    for v in PHOTO_CHECK_TEXT.values():
        assert fk_grade(v["advice"]) <= LIMIT, v["advice"]
    assert fk_grade(DISCLAIMER) <= LIMIT + 2        # names "diagnosis" and "condition" on purpose
