"""Every sentence the app shows about a result is written here, so the screening-aid positioning
(NFR8, FR9) is enforced in one place and the Flutter app holds no clinical logic.

Band wording decided 2026-11-09: high shows the result; moderate says "most likely [condition], a doctor's
check is advised"; refer says the result is inconclusive and goes straight to referral, without naming a
condition. Scabies is never shown as high (cap in app/ml/predictor.py).

Changed 2026-11-15 for model v3: on the SCIN phone test, v3's moderate results were right only 31% of the time
(high: 88%), and v3's bands refer almost nothing. The thresholds were not changed after the test; instead a
moderate result now says "possibly [condition], Lumis isn't sure" and is labeled low confidence."""
from dataclasses import dataclass

from .ml.claude_check import FITS

DISCLAIMER = ("Lumis is a screening aid, not a medical diagnosis. "
              "Only a doctor can diagnose a skin condition.")

BAND_LABELS = {"high": "High confidence", "moderate": "Low confidence", "refer": "Inconclusive"}


@dataclass(frozen=True)
class ResultText:
    show_condition: bool
    headline: str
    advice: str
    recommended_action: str      # 'see_doctor' or 'monitor'
    show_clinics: bool           # FR6: offer nearby clinics straight away


def result_text(band: str, condition_name: str, urgency: str, photo_fit: str | None = None) -> ResultText:
    """photo_fit: Claude's view of whether the photo looks typical of the condition. It can only make the advice
    more careful ("not_typical" -> see a doctor, show clinics); it never changes the band or the condition."""
    if band == "refer":
        return ResultText(
            show_condition=False,
            headline="Lumis can't tell what this is from this photo.",
            advice=("Please have it checked by a doctor. You can also try another photo: "
                    "close up, in focus and in good light."),
            recommended_action="see_doctor", show_clinics=True)

    if urgency == "see_doctor":                       # scabies: contagious, needs prescription treatment
        advice = (f"{condition_name} needs to be confirmed and treated by a doctor, "
                  "and it can spread to others, so please see a doctor soon.")
    elif band == "moderate":
        advice = ("Lumis is not sure about this result, so please don't rely on it. "
                  "Have it checked by a doctor, ideally a dermatologist.")
    else:
        advice = "If it does not improve, spreads, or worries you, please see a doctor."

    if band == "moderate":
        headline = f"Possibly {condition_name}, but Lumis isn't sure."
    else:
        headline = f"This looks most like {condition_name}."

    if photo_fit == "not_typical" and band == "high" and urgency != "see_doctor":
        advice = ("The photo does not look typical for this. Please have a doctor check it, "
                  "ideally a dermatologist.")
    see_doctor = band == "moderate" or urgency == "see_doctor" or photo_fit == "not_typical"
    return ResultText(show_condition=True, headline=headline, advice=advice,
                      recommended_action="see_doctor" if see_doctor else "monitor", show_clinics=see_doctor)


# Photo check (notebook 10): shown instead of a result. "Nothing detected" must never sound like
# "your skin is healthy", because Lumis only screens for five conditions (NFR8).
PHOTO_CHECK_TEXT = {
    "no_skin": {
        "headline": "No skin detected.",
        "advice": "Lumis couldn't find skin in this photo. Take a close-up photo of the skin you are "
                  "concerned about, in good light, filling most of the frame.",
    },
    "poor_photo": {
        "headline": "Photo not clear enough.",
        "advice": "Lumis couldn't see the skin clearly enough to check it. Retake the photo close up, "
                  "in focus and in good light, with the area filling most of the frame.",
    },
    "nothing_detected": {
        "headline": "Nothing detected.",
        "advice": "Lumis couldn't find any of the skin conditions it screens for in this photo. "
                  "This does not mean your skin is healthy: Lumis only checks for five conditions. "
                  "If you are concerned, retake the photo close up in good light, or see a doctor.",
    },
}


# ---------------------------------------------------------------- explanation (Phase 5)

# Shown after Claude's description of the photo, for the condition Lumis chose. Fixed wording, so Claude never
# states how well the photo matches in its own words. All at Flesch-Kincaid grade 8 or below (tests).
FIT_TEXT = {
    "typical": "These are common signs of {plain}.",
    "partly": "Some of these can be signs of {plain}, but not all of them.",
    "not_typical": "These are not typical signs of {plain}. Please have a doctor check it.",
}
assert set(FIT_TEXT) == set(FITS)


@dataclass(frozen=True)
class Explanation:
    what_it_is: str
    common_signs: str
    in_your_photo: str | None     # Claude's description + the fit sentence; None if Claude was skipped or late
    what_to_do: str
    photo_based: bool


def explanation(band: str, condition, claude: dict | None) -> Explanation | None:
    """The explanation under a result. condition: a Condition row; claude: the stored Claude answer (or None).
    None for an inconclusive result, which names no condition."""
    if band == "refer":
        return None
    in_photo = None
    if claude and claude.get("ok") and claude.get("seen"):
        fit = (claude.get("fit") or {}).get(condition.id)
        if fit in FIT_TEXT:
            in_photo = f"{claude['seen']} {FIT_TEXT[fit].format(plain=condition.plain_name or condition.name)}"
    return Explanation(what_it_is=condition.about or "", common_signs=condition.typical_presentation,
                       in_your_photo=in_photo, what_to_do=condition.general_guidance,
                       photo_based=in_photo is not None)


def photo_fit(condition_id: str, claude: dict | None) -> str | None:
    """Claude's fit for Lumis's condition, only if Claude's part ran and its description was shown."""
    if claude and claude.get("ok") and claude.get("seen"):
        return (claude.get("fit") or {}).get(condition_id)
    return None
