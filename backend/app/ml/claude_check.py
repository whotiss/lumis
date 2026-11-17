"""Claude's part of a screening: a skin check and a description of the photo, in one call (Phase 5).

Claude (vision) gets the photo, never the person's details, and answers four structured questions:
  1. skin_visible: is skin clearly visible?             no -> "No skin detected." (the skin gate)
  2. photo_quality / photo_problem                      recorded only
  3. seen: one or two sentences describing what the skin looks like, without naming any condition
  4. fit: for each of the five conditions, whether the visible features are "typical", "partly" typical or
     "not_typical" of it
The app shows `seen` and the fit for the condition LUMIS chose, nothing else (app/wording.py, explanation()).

Rules (declared 2026-11-17, before building; build plan, Phase 5):
  - Claude explains Lumis's result and never overrides it. The condition and band come only from the model.
    On the SCIN test cases Claude asked directly was right 55.4% of the time, Lumis v3 69.4%.
  - Claude can only make the advice more careful: no skin -> no result (as before); "not_typical" for Lumis's
    condition -> the advice recommends a doctor and shows clinics. The band is never changed.
  - The call starts when the photo arrives and runs while the model runs. The server waits for it at most
    CLAUDE_WAIT_SECONDS after the upload; if it is late, fails or its text does not pass the filter below, the
    result is shown with the general explanation only. Every outcome is recorded with the screening.
  - Question 1 is word for word the version validated in notebook 15 (skin gate). The surrounding prompt changed,
    so the gate should be re-checked on the notebook 15 sets.

History: until 2026-11-17 a third question asked which of the model's top two conditions the photo looked more like,
and could lower the band. Notebook 15's pre-declared rule did not switch that part on, so it was removed.
"""
from __future__ import annotations

import base64
import io
import json
import re
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path

import numpy as np
from PIL import Image

DEFAULT_MODEL = "claude-haiku-5-5"
PROMPT_VERSION = "explain-v1"
MAX_EDGE = 1024              # about 1,300 image tokens; plenty to judge a skin photo
FITS = ("typical", "partly", "not_typical")

SYSTEM = ("You look at skin photos for Lumis, a skin-condition screening aid used in Malaysia. You do not diagnose. "
          "Part of your answer is shown to the person who took the photo, so write it kindly, in short sentences "
          "and simple everyday English. Answer only with the requested JSON.")

PROMPT = """Look at this photo.
1. skin_visible: is human skin clearly visible and the main subject of the photo?
2. photo_quality: "good" if the skin area is in focus, close enough and lit well enough to judge its appearance; otherwise "poor", and give the main photo_problem.
3. seen: in one or two short sentences, describe what the skin in the photo looks like: color, shape, size, texture, edges and pattern, and the body area if you can tell. Start with "In your photo,". Describe only what is visible. Do not name or suggest any condition, disease, infection or cause, and do not give advice. If no skin is visible, give an empty string.
4. fit: for each condition below, how well do the visible features match its usual appearance? Answer "typical", "partly" or "not_typical".
{conditions}"""


def build_schema(classes: list[str]) -> dict:
    return {
        "type": "object",
        "properties": {
            "skin_visible": {"type": "boolean"},
            "photo_quality": {"type": "string", "enum": ["good", "poor"]},
            "photo_problem": {"type": "string",
                              "enum": ["none", "blurry", "too_dark", "too_far", "obstructed", "not_skin", "other"]},
            "seen": {"type": "string"},
            "fit": {"type": "object", "properties": {c: {"type": "string", "enum": list(FITS)} for c in classes},
                    "required": list(classes), "additionalProperties": False},
        },
        "required": ["skin_visible", "photo_quality", "photo_problem", "seen", "fit"],
        "additionalProperties": False,
    }


# ---------------------------------------------------------------- the filter on Claude's description

# Words that would turn a description into a diagnosis or a guess at a cause. Lower case, matched as word starts.
BLOCKED_WORDS = (
    "acne", "pimple", "comedo", "blackhead", "whitehead", "eczema", "dermatitis", "psoria", "scabies", "mite",
    "burrow", "tinea", "ringworm", "fung", "yeast", "candida", "infect", "bacteri", "virus", "viral", "diagnos",
    "disease", "disorder", "condition", "syndrome", "cancer", "melanoma", "carcinoma", "tumor", "tumour", "wart",
    "allerg", "rosacea", "hive", "urticaria", "shingles", "herpes", "chickenpox", "measles", "lupus", "vitiligo",
    "treat", "cream", "ointment", "medicine", "doctor", "contagious",
)
MAX_SEEN_WORDS = 50
MAX_SEEN_SENTENCES = 2
_blocked = re.compile(r"\b(" + "|".join(BLOCKED_WORDS) + r")", re.IGNORECASE)


def check_seen(text: str) -> tuple[str | None, str | None]:
    """Claude's description -> (text to show, None) or (None, reason it is not shown)."""
    text = " ".join((text or "").split())
    if not text:
        return None, "empty"
    if len(text.split()) > MAX_SEEN_WORDS:
        return None, "too long"
    if len([s for s in re.split(r"(?<=[.!?])\s+", text) if s]) > MAX_SEEN_SENTENCES:
        return None, "too many sentences"
    hit = _blocked.search(text)
    if hit:
        return None, f"blocked word: {hit.group(1).lower()}"
    if not text.lower().startswith("in your photo"):
        return None, "does not start with 'In your photo'"
    if text[-1] not in ".!":
        text += "."
    return text, None


# ---------------------------------------------------------------- the call

@dataclass(frozen=True)
class ClaudeVerdict:
    ok: bool                         # False = Claude's part was skipped (API error, refusal, bad output, late)
    skin_visible: bool | None = None
    photo_quality: str | None = None
    photo_problem: str | None = None
    seen: str | None = None          # description that passed the filter, or None
    seen_raw: str | None = None      # what Claude wrote (kept for the log and RQ3 evidence; never shown if filtered)
    filtered: str | None = None      # why the description is not shown
    fit: dict = field(default_factory=dict)
    error: str | None = None
    model: str | None = None
    prompt_version: str = PROMPT_VERSION
    ms: float | None = None          # how long the call took

    @property
    def outcome(self) -> str:
        """Short word for the logs and the Server-Timing header."""
        if not self.ok:
            return "late" if self.error == "late" else f"skipped ({self.error})"
        return f"filtered ({self.filtered})" if self.filtered else "ok"

    def to_dict(self) -> dict:
        return {**asdict(self), "outcome": self.outcome}


def prepare_image(rgb: np.ndarray, max_edge: int = MAX_EDGE) -> bytes:
    """Decoded RGB array (already turned upright) -> JPEG bytes, long edge at most max_edge."""
    im = Image.fromarray(np.ascontiguousarray(rgb))
    if max(im.size) > max_edge:
        im.thumbnail((max_edge, max_edge), Image.LANCZOS)
    b = io.BytesIO()
    im.save(b, "JPEG", quality=90)
    return b.getvalue()


def build_request(jpeg: bytes, names: dict[str, str], model: str) -> dict:
    """names: condition id -> display name, for all five classes (alphabetical, so the order hints nothing)."""
    classes = sorted(names)
    listing = "\n".join(f"   {c}: {names[c]}" for c in classes)
    return {
        "model": model,
        "max_tokens": 1024,            # thinking tokens would count toward this limit, so keep headroom
        "thinking": {"type": "disabled"},   # Haiku 5.5 thinks by default; off keeps the call fast (NFR1)
        "system": SYSTEM,
        "messages": [{"role": "user", "content": [
            {"type": "image", "source": {"type": "base64", "media_type": "image/jpeg",
                                         "data": base64.standard_b64encode(jpeg).decode()}},
            {"type": "text", "text": PROMPT.format(conditions=listing)},
        ]}],
        "extra_body": {"output_config": {"format": {"type": "json_schema", "schema": build_schema(classes)}}},
    }


def parse_response(response, classes: list[str], model: str) -> ClaudeVerdict:
    if getattr(response, "stop_reason", None) == "refusal":
        return ClaudeVerdict(ok=False, error="refusal", model=model)
    text = next((blk.text for blk in response.content if getattr(blk, "type", None) == "text"), None)
    try:
        d = json.loads(text)
        fit = {c: str(d["fit"][c]).lower() for c in classes}
        if any(v not in FITS for v in fit.values()):
            raise ValueError("unknown fit value")
        skin = bool(d["skin_visible"])
        seen, why = check_seen(str(d.get("seen", ""))) if skin else (None, "no skin")
        return ClaudeVerdict(ok=True, skin_visible=skin, photo_quality=str(d["photo_quality"]).lower(),
                             photo_problem=str(d["photo_problem"]).lower(), seen=seen,
                             seen_raw=str(d.get("seen", "")), filtered=why if skin else None, fit=fit, model=model)
    except (TypeError, ValueError, KeyError) as exc:
        stop = getattr(response, "stop_reason", None)
        return ClaudeVerdict(ok=False, error=f"unreadable output ({stop}): {type(exc).__name__}", model=model)


class ClaudeChecker:
    def __init__(self, api_key: str, model: str = DEFAULT_MODEL, timeout: float = 10.0, client=None,
                 skin_gate: bool = True):
        if client is None:
            import anthropic
            # no retries: the server only waits a few seconds for Claude anyway
            client = anthropic.Anthropic(api_key=api_key, timeout=timeout, max_retries=0)
        self.client, self.model, self.skin_gate = client, model, skin_gate

    def check(self, rgb: np.ndarray, names: dict[str, str]) -> ClaudeVerdict:
        started = time.perf_counter()
        try:
            response = self.client.messages.create(**build_request(prepare_image(rgb), names, self.model))
            verdict = parse_response(response, sorted(names), self.model)
        except Exception as exc:                       # network, rate limit, server error: skip Claude's part
            verdict = ClaudeVerdict(ok=False, error=f"api error: {type(exc).__name__}", model=self.model)
        ms = round((time.perf_counter() - started) * 1000, 1)
        return ClaudeVerdict(**{**asdict(verdict), "ms": ms})


def late(model: str, waited_ms: float) -> ClaudeVerdict:
    return ClaudeVerdict(ok=False, error="late", model=model, ms=round(waited_ms, 1))


def gate(verdict: ClaudeVerdict | None, skin_gate: bool = True) -> str:
    """'no_skin' if Claude says there is no skin (and the gate is on), else 'ok'. Never changes a band."""
    if verdict is not None and verdict.ok and skin_gate and verdict.skin_visible is False:
        return "no_skin"
    return "ok"


@dataclass(frozen=True)
class ClaudeCheckConfig:
    skin_gate: bool = False          # notebook 15, section 3
    explain: bool = False            # Phase 5: describe the photo for the explanation
    model: str = DEFAULT_MODEL

    @property
    def any(self) -> bool:
        return self.skin_gate or self.explain

    @classmethod
    def load(cls, path: str | Path) -> "ClaudeCheckConfig":
        p = Path(path)
        if not p.exists():
            return cls()
        c = json.loads(p.read_text())
        return cls(skin_gate=bool(c.get("skin_gate", False)), explain=bool(c.get("explain", False)),
                   model=c.get("model", DEFAULT_MODEL))
