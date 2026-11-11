"""Every sentence the app shows about a result is written here, so the screening-aid positioning
(NFR8, FR9) is enforced in one place and the Flutter app holds no clinical logic.

Band wording decided 2026-11-09: high shows the result; moderate says "most likely [condition], a doctor's
check is advised"; refer says the result is inconclusive and goes straight to referral, without naming a
condition. Scabies is never shown as high (cap in app/ml/predictor.py)."""
from dataclasses import dataclass

DISCLAIMER = ("Lumis is a screening aid, not a medical diagnosis. "
              "Only a doctor can diagnose a skin condition.")

BAND_LABELS = {"high": "High confidence", "moderate": "Moderate confidence", "refer": "Inconclusive"}


@dataclass(frozen=True)
class ResultText:
    show_condition: bool
    headline: str
    advice: str
    recommended_action: str      # 'see_doctor' or 'monitor'
    show_clinics: bool           # FR6: offer nearby clinics straight away


def result_text(band: str, condition_name: str, urgency: str) -> ResultText:
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
        advice = "Lumis is not sure enough to rely on this result. Please have it looked at by a doctor."
    else:
        advice = "If it does not improve, spreads, or worries you, please see a doctor."

    if band == "moderate":
        headline = f"Most likely {condition_name}, but a doctor's check is advised."
    else:
        headline = f"This looks most like {condition_name}."

    see_doctor = band == "moderate" or urgency == "see_doctor"
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
