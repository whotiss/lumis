"""Tests for the Claude check (no real API calls: a fake client stands in)."""
import io
import json
from types import SimpleNamespace

import numpy as np
import pytest
from fastapi.testclient import TestClient
from PIL import Image

from app.config import Settings
from app.main import create_app
from app.ml.claude_check import (ClaudeChecker, ClaudeVerdict, SCHEMA, apply_verdict, build_request,
                                 parse_response, prepare_image)
from tests.test_api import FakePredictor, photo, screen, signup

NAMES = {"eczema": "Eczema", "tinea": "Fungal skin infection (tinea or ringworm)"}


def fake_response(payload, stop_reason="end_turn"):
    return SimpleNamespace(stop_reason=stop_reason,
                           content=[SimpleNamespace(type="text", text=json.dumps(payload) if isinstance(payload, dict) else payload)])


class FakeClient:
    def __init__(self, payload=None, error=None):
        self.payload, self.error, self.requests = payload, error, []
        self.messages = self

    def create(self, **kw):
        self.requests.append(kw)
        if self.error:
            raise self.error
        return fake_response(self.payload)


def answer(choice="A", skin=True, quality="good"):
    return {"skin_visible": skin, "photo_quality": quality, "photo_problem": "none", "more_consistent_with": choice}


# ---------------------------------------------------------------- unit tests

def test_request_shape_and_candidate_order_hides_the_model_pick():
    img = prepare_image(np.zeros((2000, 1000, 3), np.uint8))
    assert max(Image.open(io.BytesIO(img)).size) == 1024
    r1 = build_request(img, ["tinea", "eczema"], NAMES, "m")
    r2 = build_request(img, ["eczema", "tinea"], NAMES, "m")
    assert r1["messages"] == r2["messages"]                         # same text whichever the model preferred
    text = r1["messages"][0]["content"][1]["text"]
    assert text.index("A) Eczema") < text.index("B) Fungal")
    assert r1["extra_body"]["output_config"]["format"]["schema"] == SCHEMA
    assert r1["messages"][0]["content"][0]["source"]["media_type"] == "image/jpeg"


def test_parse_maps_letters_back_to_conditions():
    v = parse_response(fake_response(answer("B")), ["tinea", "eczema"], "m")
    assert v.ok and v.choice == "tinea"                              # B = second alphabetically
    assert parse_response(fake_response(answer("neither")), ["tinea", "eczema"], "m").choice == "neither"
    assert not parse_response(fake_response("not json"), ["a", "b"], "m").ok
    assert parse_response(fake_response(answer(), "refusal"), ["a", "b"], "m").error == "refusal"


def test_rule_only_lowers():
    ok = lambda choice, **kw: ClaudeVerdict(ok=True, skin_visible=kw.get("skin", True),
                                            photo_quality=kw.get("q", "good"), photo_problem="none", choice=choice)
    assert apply_verdict("high", "eczema", ok("eczema")) == ("ok", "high")
    assert apply_verdict("high", "eczema", ok("tinea")) == ("ok", "moderate")
    assert apply_verdict("moderate", "eczema", ok("neither")) == ("ok", "refer")
    assert apply_verdict("refer", "eczema", ok("cannot_tell")) == ("ok", "refer")
    assert apply_verdict("refer", "eczema", ok("eczema")) == ("ok", "refer")      # never raised
    assert apply_verdict("high", "eczema", ok("eczema", skin=False)) == ("no_skin", "high")
    assert apply_verdict("high", "eczema", ok("eczema", q="poor")) == ("poor_photo", "high")
    assert apply_verdict("high", "eczema", ClaudeVerdict(ok=False, error="x")) == ("ok", "high")


def test_api_failure_skips_check():
    checker = ClaudeChecker("k", client=FakeClient(error=TimeoutError()))
    v = checker.check(np.zeros((50, 50, 3), np.uint8), ["eczema", "tinea"], NAMES)
    assert not v.ok and "TimeoutError" in v.error


# ---------------------------------------------------------------- through the API

@pytest.fixture
def make_env(tmp_path):
    def make(fake_client):
        settings = Settings(database_url=f"sqlite:///{(tmp_path / 'c.db').as_posix()}", image_dir=tmp_path / "img",
                            jwt_secret="test-secret-at-least-32-characters-long")
        fake = FakePredictor()
        fake.logits = np.array([0, 5.0, 0, 0, 3.0])                  # eczema high, tinea second
        checker = ClaudeChecker("k", client=fake_client) if fake_client else None
        return TestClient(create_app(settings, predictor=fake, claude_checker=checker)), fake
    return make


def test_agreeing_check_keeps_result_and_is_recorded(make_env):
    client_fake = FakeClient(answer("A"))                            # A = eczema
    client, _ = make_env(client_fake)
    with client:
        body = screen(client, signup(client)).json()
        assert body["band"] == "high" and body["condition"]["id"] == "eczema"
        from app.models import Screening
        with client.app.state.session_factory() as db:
            s = db.query(Screening).one()
            assert s.model_band == "high" and s.claude_check["choice"] == "eczema"
    assert len(client_fake.requests) == 1


def test_disagreeing_check_lowers_band(make_env):
    client, _ = make_env(FakeClient(answer("B")))                    # B = tinea
    with client:
        body = screen(client, signup(client)).json()
        assert body["band"] == "moderate" and "doctor" in body["headline"]


@pytest.mark.parametrize("payload, code", [(answer(skin=False), "no_skin"), (answer(quality="poor"), "poor_photo")])
def test_check_can_reject_photo(make_env, payload, code):
    client, _ = make_env(FakeClient(payload))
    with client:
        h = signup(client)
        r = screen(client, h)
        assert r.status_code == 422 and r.json()["detail"]["code"] == code
        assert client.get("/screenings", headers=h).json() == []


def test_api_down_keeps_model_result(make_env):
    client, _ = make_env(FakeClient(error=ConnectionError()))
    with client:
        assert screen(client, signup(client)).json()["band"] == "high"


def test_no_checker_means_no_calls(make_env):
    client, _ = make_env(None)
    with client:
        assert screen(client, signup(client)).status_code == 201
        assert client.get("/model").json()["bands"]["claude_check"] is False
