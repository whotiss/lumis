"""Claude's part of a screening (Phase 5): skin check plus a description of the photo, in parallel with the model.
No real API calls: a fake client stands in."""
import io
import json
import logging
import threading
import time
from types import SimpleNamespace

import numpy as np
import pytest
from fastapi.testclient import TestClient
from PIL import Image

from app.config import Settings
from app.consent import CONSENT_VERSION
from app.main import create_app
from app.ml.claude_check import (FITS, PROMPT_VERSION, ClaudeChecker, ClaudeCheckConfig, build_request, check_seen,
                                 gate, parse_response, prepare_image)
from app.readability import fk_grade
from app.wording import FIT_TEXT
from tests.test_api import FakePredictor, photo, screen, signup

CLASSES = ["acne", "eczema", "psoriasis", "scabies", "tinea"]
NAMES = {"acne": "Acne", "eczema": "Eczema", "psoriasis": "Psoriasis", "scabies": "Scabies",
         "tinea": "Fungal skin infection (tinea or ringworm)"}
SEEN = "In your photo, there is a dry, rough, reddish patch with blurred edges on the inner elbow."


def fake_response(payload, stop_reason="end_turn"):
    text = json.dumps(payload) if isinstance(payload, dict) else payload
    return SimpleNamespace(stop_reason=stop_reason, content=[SimpleNamespace(type="text", text=text)])


class FakeClient:
    def __init__(self, payload=None, error=None, delay=0.0):
        self.payload, self.error, self.delay, self.requests = payload, error, delay, []
        self.started = threading.Event()
        self.messages = self

    def create(self, **kw):
        self.started.set()
        self.requests.append(kw)
        time.sleep(self.delay)
        if self.error:
            raise self.error
        return fake_response(self.payload)


def answer(skin=True, seen=SEEN, eczema="typical", quality="good"):
    return {"skin_visible": skin, "photo_quality": quality, "photo_problem": "none", "seen": seen,
            "fit": {c: (eczema if c == "eczema" else "not_typical") for c in CLASSES}}


# ---------------------------------------------------------------- the request and the answer

def test_request_lists_all_conditions_and_hides_the_model_pick():
    img = prepare_image(np.zeros((2000, 1000, 3), np.uint8))
    assert max(Image.open(io.BytesIO(img)).size) == 1024
    r = build_request(img, NAMES, "m")
    text = r["messages"][0]["content"][1]["text"]
    assert all(f"{c}: {NAMES[c]}" in text for c in CLASSES)          # all five, alphabetical: no hint of Lumis's pick
    assert [text.index(f"{c}:") for c in CLASSES] == sorted(text.index(f"{c}:") for c in CLASSES)
    schema = r["extra_body"]["output_config"]["format"]["schema"]
    assert schema["properties"]["fit"]["required"] == CLASSES
    assert r["thinking"] == {"type": "disabled"}
    # the skin question is word for word the version validated in notebook 15
    assert "1. skin_visible: is human skin clearly visible and the main subject of the photo?" in text


def test_parse_keeps_a_good_description():
    v = parse_response(fake_response(answer()), CLASSES, "m")
    assert v.ok and v.seen == SEEN and v.fit["eczema"] == "typical" and v.outcome == "ok"
    assert v.prompt_version == PROMPT_VERSION


@pytest.mark.parametrize("payload,error", [("not json", "unreadable"), ('{"skin_vis', "max_tokens")])
def test_parse_bad_output_skips(payload, error):
    v = parse_response(fake_response(payload, "max_tokens" if error == "max_tokens" else "end_turn"), CLASSES, "m")
    assert not v.ok and error in v.error


def test_parse_refusal_and_unknown_fit():
    assert parse_response(fake_response(answer(), "refusal"), CLASSES, "m").error == "refusal"
    bad = answer()
    bad["fit"]["acne"] = "maybe"
    assert not parse_response(fake_response(bad), CLASSES, "m").ok


@pytest.mark.parametrize("text,reason", [
    ("In your photo, there are red spots that look like acne.", "blocked word: acne"),
    ("In your photo, this looks like a fungal infection.", "blocked word: fung"),
    ("In your photo, a patch. It is red. It is dry.", "too many sentences"),
    ("In your photo, " + "red " * 60, "too long"),
    ("There is a red patch on the arm.", "does not start"),
    ("In your photo, a red patch. You should see a doctor.", "blocked word: doctor"),
    ("", "empty"),
])
def test_filter_blocks_diagnosis_and_long_text(text, reason):
    shown, why = check_seen(text)
    assert shown is None and reason in why


def test_filter_passes_plain_description():
    assert check_seen("In your photo, a round, scaly ring with a clear center on the forearm") == (
        "In your photo, a round, scaly ring with a clear center on the forearm.", None)


def test_filtered_description_is_recorded_not_shown():
    v = parse_response(fake_response(answer(seen="In your photo, this is eczema.")), CLASSES, "m")
    assert v.ok and v.seen is None and v.seen_raw == "In your photo, this is eczema." and "eczema" in v.filtered
    assert v.outcome.startswith("filtered")


def test_gate_only_stops_no_skin():
    ok = parse_response(fake_response(answer()), CLASSES, "m")
    no = parse_response(fake_response(answer(skin=False, seen="")), CLASSES, "m")
    assert gate(ok) == "ok" and gate(no) == "no_skin" and gate(no, skin_gate=False) == "ok" and gate(None) == "ok"


def test_config(tmp_path):
    assert not ClaudeCheckConfig.load(tmp_path / "missing.json").any
    p = tmp_path / "c.json"
    p.write_text(json.dumps({"skin_gate": True, "explain": True}))
    c = ClaudeCheckConfig.load(p)
    assert c.any and c.skin_gate and c.explain


def test_api_failure_is_recorded_with_time():
    v = ClaudeChecker("k", client=FakeClient(error=TimeoutError())).check(np.zeros((50, 50, 3), np.uint8), NAMES)
    assert not v.ok and "TimeoutError" in v.error and v.ms is not None


def test_fixed_sentences_read_at_grade_8_or_below():
    assert set(FIT_TEXT) == set(FITS)
    for plain in ["acne", "a fungal skin infection (tinea)"]:
        for t in FIT_TEXT.values():
            assert fk_grade(t.format(plain=plain)) <= 8, t


# ---------------------------------------------------------------- through the API

@pytest.fixture
def make_env(tmp_path):
    def make(fake_client, wait=4.5, logits=(0, 5.0, 0, 0, 3.0)):         # eczema high by default
        settings = Settings(database_url=f"sqlite:///{(tmp_path / 'c.db').as_posix()}", image_dir=tmp_path / "img",
                            jwt_secret="test-secret-at-least-32-characters-long", claude_wait_seconds=wait,
                            _env_file=None)
        fake = FakePredictor()
        fake.logits = np.array(logits)
        checker = ClaudeChecker("k", client=fake_client) if fake_client else None
        return TestClient(create_app(settings, predictor=fake, claude_checker=checker)), fake
    return make


def test_result_and_explanation_arrive_together(make_env):
    fc = FakeClient(answer())
    client, _ = make_env(fc)
    with client:
        h = signup(client)
        r = screen(client, h)
        body = r.json()
        assert body["band"] == "high" and body["condition"]["id"] == "eczema"
        e = body["explanation"]
        assert e["photo_based"] is True
        assert e["in_your_photo"] == SEEN + " These are common signs of eczema."
        assert e["what_it_is"] and e["common_signs"] and e["what_to_do"]
        assert 'desc="ok"' in r.headers["server-timing"] and "screening;dur=" in r.headers["server-timing"]
        from app.models import Screening
        with client.app.state.session_factory() as db:          # the explanation log
            log = db.query(Screening).one().claude_check
            assert log["prompt_version"] == PROMPT_VERSION and log["outcome"] == "ok" and log["ms"] is not None
        # history shows the same explanation, rebuilt from the log
        assert client.get("/screenings", headers=h).json()[0]["explanation"] == e
    assert len(fc.requests) == 1


def test_claude_never_changes_the_condition_or_band(make_env):
    client, _ = make_env(FakeClient(answer(eczema="not_typical")))
    with client:
        body = screen(client, signup(client)).json()
        assert body["band"] == "high" and body["condition"]["id"] == "eczema"      # unchanged
        # ...but the advice becomes more careful
        assert body["recommended_action"] == "see_doctor" and body["show_clinics"] is True
        assert "not typical signs of eczema" in body["explanation"]["in_your_photo"]
        assert "doctor" in body["advice"]


def test_claude_runs_while_the_model_runs(make_env):
    """Claude takes 0.5 s and the model 0.5 s: in parallel the screening takes about 0.5 s, not 1 s."""
    fc = FakeClient(answer(), delay=0.5)
    client, fake = make_env(fc)
    original = fake.predict

    def slow_predict(data):
        assert fc.started.wait(2), "Claude's call should already have started"
        time.sleep(0.5)
        return original(data)
    fake.predict = slow_predict
    with client:
        h = signup(client)
        t = time.perf_counter()
        r = screen(client, h)
        took = time.perf_counter() - t
    assert r.status_code == 201 and r.json()["explanation"]["photo_based"]
    assert took < 0.9


def test_late_claude_does_not_hold_up_the_result(make_env, caplog):
    client, _ = make_env(FakeClient(answer(), delay=1.5), wait=0.3)
    with client, caplog.at_level(logging.WARNING, logger="lumis.screenings"):
        t = time.perf_counter()
        r = screen(client, signup(client))
        took = time.perf_counter() - t
    body = r.json()
    assert r.status_code == 201 and took < 1.2
    assert body["explanation"]["photo_based"] is False and body["explanation"]["in_your_photo"] is None
    assert body["explanation"]["what_it_is"]                                     # general text still shown
    assert 'desc="late"' in r.headers["server-timing"] and "Claude check late" in caplog.text


def test_api_down_keeps_result_with_general_explanation(make_env):
    client, _ = make_env(FakeClient(error=ConnectionError()))
    with client:
        body = screen(client, signup(client)).json()
        assert body["band"] == "high" and body["explanation"]["photo_based"] is False


def test_no_skin_stops_the_result(make_env):
    client, _ = make_env(FakeClient(answer(skin=False, seen="")))
    with client:
        h = signup(client)
        r = screen(client, h)
        assert r.status_code == 422 and r.json()["detail"]["code"] == "no_skin"
        assert client.get("/screenings", headers=h).json() == []


def test_inconclusive_result_has_no_explanation(make_env):
    client, fake = make_env(FakeClient(answer()), logits=(1.0, 1.0, 1.0, 1.0, 1.0))   # flat: refer band
    with client:
        body = screen(client, signup(client)).json()
        assert body["band"] == "refer" and body["condition"] is None and body["explanation"] is None


def test_no_checker_means_no_calls_and_general_text(make_env):
    client, _ = make_env(None)
    with client:
        body = screen(client, signup(client)).json()
        assert body["explanation"]["photo_based"] is False and body["explanation"]["common_signs"]
        bands = client.get("/model").json()["bands"]
        assert bands["claude_check"] is False and bands["claude_explains"] is False


def test_skipped_part_is_reported(make_env, caplog):
    """A wrong key or an outage must be visible in the timing header and the logs."""
    class Failing:
        class messages:
            @staticmethod
            def create(**kw):
                raise PermissionError("bad key")

    client, _ = make_env(Failing())
    with client:
        h = {"Authorization": f"Bearer {client.post('/auth/register', json={'email': 'k@example.com', 'password': 'correct horse', 'accept_consent_version': CONSENT_VERSION, 'confirm_adult': True}).json()['access_token']}"}
        with caplog.at_level(logging.WARNING, logger="lumis.screenings"):
            r = client.post("/screenings", headers=h, files={"image": ("p.jpg", photo(), "image/jpeg")})
    assert r.status_code == 201
    assert 'desc="skipped (api error: PermissionError)"' in r.headers["server-timing"]
    assert "Claude check skipped (api error: PermissionError)" in caplog.text


def test_smoke_test_flags_a_skipped_claude_check():
    from scripts.smoke_test import check_claude
    failures = []
    check_claude(True, 'preprocess;dur=1, claude;dur=812.0;desc="ok"', failures)
    assert failures == []
    check_claude(True, 'model;dur=3, claude;dur=300.2;desc="skipped (api error: AuthenticationError)"', failures)
    assert "did not run" in failures[0]
    check_claude(True, 'claude;dur=900.0;desc="filtered (blocked word: acne)"', failures)
    assert len(failures) == 1                          # filtered is allowed: the result showed the general text
    check_claude(True, 'claude;dur=4500.0;desc="late"', failures)
    assert "did not run" in failures[1]
    check_claude(False, "model;dur=3", failures)
    assert len(failures) == 2
