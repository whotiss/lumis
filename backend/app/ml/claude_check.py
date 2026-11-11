"""Claude check: a second look at each photo before Lumis shows a result.

Claude (vision) answers three structured questions about the photo:
  1. is skin clearly visible?                         no  -> "No skin detected."
  2. is the photo good enough to judge?               no  -> "Photo not clear enough." (retake)
  3. of the model's two most likely conditions, which one does the visible finding look more like
     (or neither, or cannot tell)?

Rule (decided 2026-11-11, before any evaluation): Claude can only make Lumis MORE careful.
  - Claude picks the model's top condition                -> result unchanged
  - Claude picks the second, "neither" or "cannot tell"   -> band lowered one step (high -> moderate -> refer)
  - Claude never raises a band and never introduces a condition of its own.
  - If the API fails, refuses, or times out, the check is skipped and the model's result stands (recorded).
Claude's answer is never shown to the user. The two candidates are given in alphabetical order, so their
order does not hint which one the model preferred.

Two parts, each switched on separately by notebook 15 on its own pre-declared rule (models/claude_check.json):
  "skin_gate": true  -> only question 1 is used (no skin -> "No skin detected"); bands are never changed.
  "enabled": true    -> all three questions are used, as described above.
"""
from __future__ import annotations

import base64
import io
import json
from dataclasses import asdict, dataclass
from pathlib import Path

import numpy as np
from PIL import Image

DEFAULT_MODEL = "claude-haiku-5-5"
MAX_EDGE = 1024              # about 1,300 image tokens; plenty to judge a skin photo

SYSTEM = ("You check photos for Lumis, a skin-condition screening aid. You do not diagnose, and your answer is "
          "never shown to the person who took the photo. Answer only with the requested JSON.")

PROMPT = """Look at this photo.
1. skin_visible: is human skin clearly visible and the main subject of the photo?
2. photo_quality: "good" if the skin area is in focus, close enough and lit well enough to judge its appearance; otherwise "poor", and give the main photo_problem.
3. A screening model says the photo most likely shows one of these two conditions:
   A) {a}
   B) {b}
   Which one is the visible skin finding more consistent with? Answer "A", "B", "neither" (it looks like something else, or like normal skin), or "cannot_tell"."""

SCHEMA = {
    "type": "object",
    "properties": {
        "skin_visible": {"type": "boolean"},
        "photo_quality": {"type": "string", "enum": ["good", "poor"]},
        "photo_problem": {"type": "string",
                          "enum": ["none", "blurry", "too_dark", "too_far", "obstructed", "not_skin", "other"]},
        "more_consistent_with": {"type": "string", "enum": ["A", "B", "neither", "cannot_tell"]},
    },
    "required": ["skin_visible", "photo_quality", "photo_problem", "more_consistent_with"],
    "additionalProperties": False,
}


@dataclass(frozen=True)
class ClaudeVerdict:
    ok: bool                         # False = check skipped (API error, refusal, bad output)
    skin_visible: bool | None = None
    photo_quality: str | None = None
    photo_problem: str | None = None
    choice: str | None = None        # a condition id, "neither" or "cannot_tell"
    error: str | None = None
    model: str | None = None

    def to_dict(self) -> dict:
        return asdict(self)


def prepare_image(rgb: np.ndarray, max_edge: int = MAX_EDGE) -> bytes:
    """Decoded RGB array (already turned upright) -> JPEG bytes, long edge at most max_edge."""
    im = Image.fromarray(np.ascontiguousarray(rgb))
    if max(im.size) > max_edge:
        im.thumbnail((max_edge, max_edge), Image.LANCZOS)
    b = io.BytesIO()
    im.save(b, "JPEG", quality=90)
    return b.getvalue()


def build_request(jpeg: bytes, candidates: list[str], names: dict[str, str], model: str) -> dict:
    a, b = sorted(candidates)
    return {
        "model": model,
        "max_tokens": 200,
        "system": SYSTEM,
        "messages": [{"role": "user", "content": [
            {"type": "image", "source": {"type": "base64", "media_type": "image/jpeg",
                                         "data": base64.standard_b64encode(jpeg).decode()}},
            {"type": "text", "text": PROMPT.format(a=names.get(a, a), b=names.get(b, b))},
        ]}],
        "extra_body": {"output_config": {"format": {"type": "json_schema", "schema": SCHEMA}}},
    }


def parse_response(response, candidates: list[str], model: str) -> ClaudeVerdict:
    if getattr(response, "stop_reason", None) == "refusal":
        return ClaudeVerdict(ok=False, error="refusal", model=model)
    text = next((blk.text for blk in response.content if getattr(blk, "type", None) == "text"), None)
    try:
        d = json.loads(text)
        pick = str(d["more_consistent_with"]).strip()
        a, b = sorted(candidates)
        choice = {"a": a, "b": b, "neither": "neither", "cannot_tell": "cannot_tell"}[pick.lower()]
        return ClaudeVerdict(ok=True, skin_visible=bool(d["skin_visible"]),
                             photo_quality=str(d["photo_quality"]).lower(),
                             photo_problem=str(d["photo_problem"]).lower(), choice=choice, model=model)
    except (TypeError, ValueError, KeyError) as exc:
        return ClaudeVerdict(ok=False, error=f"unreadable output: {type(exc).__name__}", model=model)


class ClaudeChecker:
    def __init__(self, api_key: str, model: str = DEFAULT_MODEL, timeout: float = 20.0, client=None,
                 skin_gate: bool = True, full: bool = True):
        if client is None:
            import anthropic
            client = anthropic.Anthropic(api_key=api_key, timeout=timeout, max_retries=1)
        self.client, self.model = client, model
        self.skin_gate, self.full = skin_gate, full          # which parts of the rule are switched on

    def check(self, rgb: np.ndarray, candidates: list[str], names: dict[str, str]) -> ClaudeVerdict:
        try:
            response = self.client.messages.create(**build_request(prepare_image(rgb), candidates, names, self.model))
        except Exception as exc:                       # network, rate limit, server error: skip the check
            return ClaudeVerdict(ok=False, error=f"api error: {type(exc).__name__}", model=self.model)
        return parse_response(response, candidates, self.model)


LOWER = {"high": "moderate", "moderate": "refer", "refer": "refer"}


def apply_verdict(band: str, top: str, verdict: ClaudeVerdict, skin_gate: bool = True,
                  full: bool = True) -> tuple[str, str]:
    """(model band, model top condition, verdict) -> (status, band). Status is 'ok', 'no_skin' or 'poor_photo'.
    Never raises a band. skin_gate / full say which parts of the rule are switched on."""
    if not verdict.ok:
        return "ok", band
    if (skin_gate or full) and verdict.skin_visible is False:
        return "no_skin", band
    if not full:
        return "ok", band
    if verdict.photo_quality == "poor":
        return "poor_photo", band
    if verdict.choice == top:
        return "ok", band
    return "ok", LOWER[band]


@dataclass(frozen=True)
class ClaudeCheckConfig:
    enabled: bool                    # full check (notebook 15, section 2)
    model: str = DEFAULT_MODEL
    skin_gate: bool = False          # "no skin" question only (notebook 15, section 3)

    @property
    def any(self) -> bool:
        return self.enabled or self.skin_gate

    @classmethod
    def load(cls, path: str | Path) -> "ClaudeCheckConfig":
        p = Path(path)
        if not p.exists():
            return cls(enabled=False)
        c = json.loads(p.read_text())
        return cls(enabled=bool(c.get("enabled", False)), model=c.get("model", DEFAULT_MODEL),
                   skin_gate=bool(c.get("skin_gate", False)))
