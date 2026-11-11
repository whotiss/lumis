"""API tests. A fake model gives chosen outputs so every band and rule can be tested;
the last test runs the real model when backend/models/ has it."""
import dataclasses
import io
from pathlib import Path

import numpy as np
import pytest
from fastapi.testclient import TestClient
from PIL import Image

from app.config import Settings
from app.main import create_app
from app.ml.predictor import ModelConfig, postprocess, preprocess
from app.wording import DISCLAIMER

MODELS = Path(__file__).resolve().parents[1] / "models"
CLASSES = ["acne", "eczema", "psoriasis", "scabies", "tinea"]


class FakePredictor:
    """Real preprocessing (so bad files are rejected the same way), chosen logits."""
    def __init__(self):
        self.config = ModelConfig(model_version="fake-v0", classes=CLASSES, img_size=224, temperature=1.0,
                                  logit_adjust=[0.0] * 5, high_from=0.74, refer_below=0.52,
                                  cap_at_moderate=["scabies"])
        self.logits = np.array([5.0, 0, 0, 0, 0])
        self.status = "ok"

    def predict(self, data):
        preprocess(data, 224)
        return dataclasses.replace(postprocess(self.logits, self.config), status=self.status)


def photo(fmt="JPEG"):
    rng = np.random.default_rng(0)
    b = io.BytesIO()
    Image.fromarray(rng.integers(0, 255, (300, 400, 3), dtype=np.uint8)).save(b, fmt)
    return b.getvalue()


@pytest.fixture
def env(tmp_path):
    settings = Settings(database_url=f"sqlite:///{(tmp_path / 'test.db').as_posix()}", image_dir=tmp_path / "img",
                        jwt_secret="test-secret-at-least-32-characters-long", max_upload_mb=1)
    fake = FakePredictor()
    with TestClient(create_app(settings, predictor=fake)) as client:
        yield client, fake, tmp_path / "img"


def signup(client, email="zan@example.com", consent_storage=True):
    r = client.post("/auth/register", json={"email": email, "password": "correct horse", "consent_storage": consent_storage})
    assert r.status_code == 201, r.text
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


def screen(client, headers, data=None, **form):
    return client.post("/screenings", headers=headers, files={"image": ("p.jpg", data or photo(), "image/jpeg")},
                       data=form)


# ---------------------------------------------------------------- accounts

def test_register_login_me(env):
    client, _, _ = env
    signup(client, "Zan@Example.com")
    r = client.post("/auth/login", data={"username": "zan@example.com", "password": "correct horse"})
    assert r.status_code == 200
    me = client.get("/me", headers={"Authorization": f"Bearer {r.json()['access_token']}"}).json()
    assert me["email"] == "zan@example.com" and me["consent_storage"] is True


def test_account_errors(env):
    client, _, _ = env
    signup(client)
    assert client.post("/auth/register", json={"email": "zan@example.com", "password": "another one"}).status_code == 409
    assert client.post("/auth/register", json={"email": "x@example.com", "password": "short"}).status_code == 422
    assert client.post("/auth/login", data={"username": "zan@example.com", "password": "wrong pass"}).status_code == 401
    assert client.get("/me").status_code == 401
    assert client.get("/me", headers={"Authorization": "Bearer nonsense"}).status_code == 401


def test_password_is_salted_hash(env):
    client, _, _ = env
    signup(client, "a@example.com")
    signup(client, "b@example.com")
    from app.models import User
    with client.app.state.session_factory() as db:
        hashes = [u.password_hash for u in db.query(User)]
    assert all(h.startswith("$argon2id$") for h in hashes)
    assert hashes[0] != hashes[1]                      # same password, different salt
    assert not any("correct horse" in h for h in hashes)


def test_consent_is_timestamped(env):
    client, _, _ = env
    h = signup(client, consent_storage=False)
    r = client.patch("/me/consent", headers=h, json={"consent_location": True})
    assert r.json()["consent_location"] is True
    from app.models import User
    with client.app.state.session_factory() as db:
        assert db.query(User).one().consent_location_at is not None


# ---------------------------------------------------------------- results and wording

def test_high_band(env):
    client, fake, _ = env
    h = signup(client)
    r = screen(client, h, duration="1_to_4_weeks", itchy="true")
    assert r.status_code == 201, r.text
    body = r.json()
    assert body["band"] == "high" and body["band_label"] == "High confidence"
    assert body["condition"] == {"id": "acne", "name": "Acne"} and body["confidence"] > 0.9
    assert body["recommended_action"] == "monitor" and body["show_clinics"] is False
    assert body["disclaimer"] == DISCLAIMER
    assert body["symptom_details"] == {"duration": "1_to_4_weeks", "itchy": True, "changing": None}
    assert body["created_at"].endswith(("Z", "+00:00"))                       # always UTC


def test_moderate_band(env):
    client, fake, _ = env
    fake.logits = np.array([0, 1.8, 0, 0, 0])            # eczema at about 0.60
    body = screen(client, signup(client)).json()
    assert body["band"] == "moderate"
    assert body["headline"] == "Most likely Eczema, but a doctor's check is advised."
    assert body["recommended_action"] == "see_doctor" and body["show_clinics"] is True


def test_refer_band_names_no_condition(env):
    client, fake, _ = env
    fake.logits = np.array([0.3, 0, 0, 0, 0])
    body = screen(client, signup(client)).json()
    assert body["band"] == "refer" and body["band_label"] == "Inconclusive"
    assert body["condition"] is None and body["confidence"] is None
    assert "can't tell" in body["headline"] and body["show_clinics"] is True


def test_scabies_never_high_and_always_referred(env):
    client, fake, _ = env
    fake.logits = np.array([0, 0, 0, 6.0, 0])
    body = screen(client, signup(client)).json()
    assert body["band"] == "moderate" and body["condition"]["id"] == "scabies"
    assert body["recommended_action"] == "see_doctor" and "spread" in body["advice"]


def test_no_diagnostic_wording_anywhere(env):
    client, fake, _ = env
    h = signup(client)
    for logits in ([5, 0, 0, 0, 0], [0, 1.8, 0, 0, 0], [0.3, 0, 0, 0, 0], [0, 0, 0, 6, 0], [0, 0, 0, 0, 5]):
        fake.logits = np.array(logits, dtype=float)
        body = screen(client, h).json()
        text = (body["headline"] + " " + body["advice"]).lower()
        assert "you have" not in text and "diagnosed" not in text and "diagnosis" not in text


# ---------------------------------------------------------------- photo check

@pytest.mark.parametrize("code, headline", [("no_skin", "No skin detected."), ("nothing_detected", "Nothing detected.")])
def test_photo_check_rejections(env, code, headline):
    client, fake, img_dir = env
    fake.status = code
    h = signup(client)
    r = screen(client, h)
    assert r.status_code == 422
    detail = r.json()["detail"]
    assert detail["code"] == code and detail["headline"] == headline and detail["disclaimer"] == DISCLAIMER
    assert client.get("/screenings", headers=h).json() == []        # nothing saved
    assert list(img_dir.rglob("*.jpg")) == []                         # photo not kept


def test_nothing_detected_never_says_healthy(env):
    client, fake, _ = env
    fake.status = "nothing_detected"
    advice = screen(client, signup(client)).json()["detail"]["advice"].lower()
    assert "does not mean your skin is healthy" in advice


# ---------------------------------------------------------------- uploads

def test_bad_uploads(env):
    client, _, _ = env
    h = signup(client)
    assert screen(client, h, data=b"definitely not a photo").status_code == 415
    assert screen(client, h, data=b"\xff" * (1024 * 1024 + 10)).status_code == 413
    assert screen(client, h, duration="forever").status_code == 422
    assert screen(client, {}).status_code == 401


def test_png_and_webp_accepted(env):
    client, _, _ = env
    h = signup(client)
    for fmt in ("PNG", "WEBP"):
        assert screen(client, h, data=photo(fmt)).status_code == 201


# ---------------------------------------------------------------- storage consent, history, delete

def test_image_kept_only_with_consent(env):
    client, _, img_dir = env
    with_consent = screen(client, signup(client, "a@example.com", True)).json()
    without = screen(client, signup(client, "b@example.com", False)).json()
    assert with_consent["image_available"] is True and without["image_available"] is False
    assert len(list(img_dir.rglob("*.jpg"))) == 1


def test_history_and_privacy_between_users(env):
    client, _, _ = env
    a, b = signup(client, "a@example.com"), signup(client, "b@example.com")
    first, second = screen(client, a).json(), screen(client, a).json()
    hist = client.get("/screenings", headers=a).json()
    assert [s["id"] for s in hist] == [second["id"], first["id"]]          # newest first
    assert client.get("/screenings", headers=b).json() == []
    assert client.get(f"/screenings/{first['id']}", headers=b).status_code == 404
    assert client.get(f"/screenings/{first['id']}/image", headers=b).status_code == 404
    img = client.get(f"/screenings/{first['id']}/image", headers=a)
    assert img.status_code == 200 and img.headers["content-type"] == "image/jpeg"


def test_delete_screening_removes_image(env):
    client, _, img_dir = env
    h = signup(client)
    s = screen(client, h).json()
    assert client.delete(f"/screenings/{s['id']}", headers=h).status_code == 204
    assert client.get(f"/screenings/{s['id']}", headers=h).status_code == 404
    assert list(img_dir.rglob("*.jpg")) == []


def test_delete_account_removes_everything(env):
    client, _, img_dir = env
    h = signup(client)
    screen(client, h), screen(client, h)
    assert client.delete("/me", headers=h).status_code == 204
    assert client.get("/me", headers=h).status_code == 401
    assert list(img_dir.rglob("*.jpg")) == []
    from app.models import Screening
    with client.app.state.session_factory() as db:
        assert db.query(Screening).count() == 0


# ---------------------------------------------------------------- reference data

def test_conditions_and_model_info(env):
    client, _, _ = env
    conds = client.get("/conditions").json()
    assert sorted(c["id"] for c in conds) == CLASSES
    assert all(c["typical_presentation"] and c["general_guidance"] for c in conds)
    info = client.get("/model").json()
    assert info["model_version"] == "fake-v0" and info["bands"]["never_high"] == ["scabies"]
    assert client.get("/health").json()["status"] == "ok"


# ---------------------------------------------------------------- the real model

@pytest.mark.skipif(not (MODELS / "lumis_model_config.json").exists(), reason="model not downloaded yet")
def test_real_model_end_to_end(tmp_path):
    settings = Settings(database_url=f"sqlite:///{(tmp_path / 't.db').as_posix()}", image_dir=tmp_path / "img",
                        jwt_secret="test-secret-at-least-32-characters-long", model_dir=MODELS)
    with TestClient(create_app(settings)) as client:
        body = screen(client, signup(client)).json()
        assert body["band"] in {"high", "moderate", "refer"}
        assert body["model_version"] == "lumis-effb0-v1"
        assert client.get("/model").json()["test_results"]["accuracy"] == pytest.approx(0.6553, abs=1e-3)
        if (MODELS / "photo_check.json").exists():                    # a plain blue picture is not skin
            b = io.BytesIO()
            Image.new("RGB", (400, 300), (30, 80, 200)).save(b, "JPEG")
            r = screen(client, signup(client, "blue@example.com"), data=b.getvalue())
            assert r.status_code == 422 and r.json()["detail"]["code"] == "no_skin"
