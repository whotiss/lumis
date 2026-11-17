"""Consent (NFR4, Malaysia's PDPA): explicit, versioned, in English and Malay, and checked before any photo is
analyzed or sent anywhere."""
import os
import re

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, inspect, text

from app.config import Settings
from app.consent import CONSENT_VERSION, ITEMS, consent_document, text_fingerprint
from app.main import create_app

from .test_api import FakePredictor, photo

SECRET = "test-secret-at-least-32-characters-long"

# If this fails, the consent wording changed. Anything a person agrees to needs a new CONSENT_VERSION in
# app/consent.py (everyone is then asked again), then update both values here.
APPROVED = {"2026-11-17": "65d40a50b6aaccd0"}


def test_text_changes_need_a_new_version():
    assert CONSENT_VERSION in APPROVED, "new CONSENT_VERSION: add it to APPROVED with the new fingerprint"
    assert APPROVED[CONSENT_VERSION] == text_fingerprint(), (
        f"The consent text changed (fingerprint {text_fingerprint()}). If what people agree to changed, give "
        f"CONSENT_VERSION a new date; then put the version and this fingerprint in APPROVED.")


@pytest.fixture
def app_client(tmp_path):
    settings = Settings(database_url=f"sqlite:///{(tmp_path / 'c.db').as_posix()}", image_dir=tmp_path / "img",
                        jwt_secret=SECRET, contact_email="lumis@example.com")
    with TestClient(create_app(settings, predictor=FakePredictor())) as client:
        yield client


def register(client, **over):
    body = {"email": "a@example.com", "password": "correct horse", "accept_consent_version": CONSENT_VERSION,
            "confirm_adult": True, **over}
    return client.post("/auth/register", json=body)


def auth(r):
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


# ---------------------------------------------------------------- the text

@pytest.mark.parametrize("lang", ["en", "ms"])
def test_consent_text_in_both_languages(app_client, lang):
    doc = app_client.get("/consent", params={"lang": lang}).json()
    assert doc["version"] == CONSENT_VERSION and doc["language"] == lang
    assert [i["id"] for i in doc["items"]] == ["processing", "adult", "storage", "location"]
    assert [i["required"] for i in doc["items"]] == [True, True, False, False]
    body = " ".join(s["body"] for s in doc["sections"])
    for must in ["Singapore" if lang == "en" else "Singapura", "Anthropic", "30", "18", "lumis@example.com", "2010"]:
        assert must in body, must
    assert "{contact}" not in body


def test_both_languages_say_the_same_things():
    en, ms = consent_document("en", "x@example.com"), consent_document("ms", "x@example.com")
    assert len(en["sections"]) == len(ms["sections"]) and [i["id"] for i in en["items"]] == [i["id"] for i in ms["items"]]
    numbers = lambda d: sorted(re.findall(r"\d+", " ".join(s["body"] for s in d["sections"])))
    assert numbers(en) == numbers(ms)                                # same facts: 18, 30 days, 2 years, 2010


def test_unknown_language_and_defaults(app_client):
    assert app_client.get("/consent", params={"lang": "zh"}).status_code == 422
    assert app_client.get("/consent").json()["language"] == "en"


def test_required_items_never_start_ticked():
    assert dict(ITEMS) == {"processing": True, "adult": True, "storage": False, "location": False}


# ---------------------------------------------------------------- registering

def test_register_records_explicit_consent(app_client):
    r = register(app_client, consent_storage=True, consent_location=True)
    assert r.status_code == 201
    me = app_client.get("/me", headers=auth(r)).json()
    assert me["consent_version"] == CONSENT_VERSION and me["consent_current"] is True
    assert me["consent_storage"] is True and me["consent_location"] is True


@pytest.mark.parametrize("over,status,code", [
    ({"accept_consent_version": "2020-01-01"}, 409, "consent_outdated"),     # agreed to an old text
    ({"confirm_adult": False}, 422, "not_adult"),
])
def test_register_refused_without_valid_consent(app_client, over, status, code):
    r = register(app_client, **over)
    assert r.status_code == status and r.json()["detail"]["code"] == code
    assert app_client.post("/auth/login", data={"username": "a@example.com", "password": "correct horse"}).status_code == 401


def test_register_refused_when_boxes_are_missing(app_client):
    r = app_client.post("/auth/register", json={"email": "a@example.com", "password": "correct horse"})
    assert r.status_code == 422                                       # no implied consent


# ---------------------------------------------------------------- screenings wait for current consent

def test_screening_blocked_until_current_consent(app_client, monkeypatch):
    h = auth(register(app_client))
    send = lambda: app_client.post("/screenings", headers=h, files={"image": ("p.jpg", photo(), "image/jpeg")})
    assert send().status_code == 201

    # the text changes: the next screening is refused before the photo is even read
    monkeypatch.setattr("app.routers.auth.CONSENT_VERSION", "2099-01-01")
    monkeypatch.setattr("app.routers.screenings.CONSENT_VERSION", "2099-01-01")
    calls = []
    app_client.app.state.predictor.predict = lambda data: calls.append(1)
    r = send()
    assert r.status_code == 403 and r.json()["detail"]["code"] == "consent_required" and not calls
    assert app_client.get("/me", headers=h).json()["consent_current"] is False

    # agreeing to an old version does not count; agreeing to the new one does
    assert app_client.post("/me/consent/accept", headers=h, json={"version": CONSENT_VERSION, "confirm_adult": True}).status_code == 409
    r = app_client.post("/me/consent/accept", headers=h, json={"version": "2099-01-01", "confirm_adult": True})
    assert r.status_code == 200 and r.json()["consent_current"] is True


def test_history_and_deletion_stay_available_without_current_consent(app_client, monkeypatch):
    """Someone who does not agree to a new text must still be able to see and delete their data."""
    h = auth(register(app_client))
    sid = app_client.post("/screenings", headers=h, files={"image": ("p.jpg", photo(), "image/jpeg")}).json()["id"]
    monkeypatch.setattr("app.routers.auth.CONSENT_VERSION", "2099-01-01")
    monkeypatch.setattr("app.routers.screenings.CONSENT_VERSION", "2099-01-01")
    assert len(app_client.get("/screenings", headers=h).json()) == 1
    assert app_client.delete(f"/screenings/{sid}", headers=h).status_code == 204
    assert app_client.delete("/me", headers=h).status_code == 204


# ---------------------------------------------------------------- existing databases get the new columns

def _old_database(url):
    """A users table as it was before consent was recorded (the live database has this shape)."""
    engine = create_engine(url)
    with engine.begin() as conn:
        for t in ("screenings", "users", "conditions"):
            conn.execute(text(f"DROP TABLE IF EXISTS {t} CASCADE" if url.startswith("postgres") else f"DROP TABLE IF EXISTS {t}"))
        conn.execute(text("CREATE TABLE users (id INTEGER PRIMARY KEY, email VARCHAR(254) UNIQUE, "
                          "password_hash VARCHAR(255), consent_storage BOOLEAN, consent_storage_at TIMESTAMP, "
                          "consent_location BOOLEAN, consent_location_at TIMESTAMP, created_at TIMESTAMP)"))
        conn.execute(text("INSERT INTO users (id, email, password_hash, consent_storage, consent_location, created_at) "
                          "VALUES (1, 'old@example.com', 'x', false, false, CURRENT_TIMESTAMP)"))
    engine.dispose()


def _check_upgrade(url, settings_kw):
    _old_database(url)
    with TestClient(create_app(Settings(database_url=url, jwt_secret=SECRET, **settings_kw),
                               predictor=FakePredictor())) as client:
        cols = {c["name"] for c in inspect(create_engine(url)).get_columns("users")}
        assert {"terms_version", "terms_accepted_at", "adult_confirmed"} <= cols
        from app.models import User
        with client.app.state.session_factory() as db:
            old = db.get(User, 1)
            assert old.email == "old@example.com" and old.terms_version is None   # must agree before screening
    with TestClient(create_app(Settings(database_url=url, jwt_secret=SECRET, **settings_kw),
                               predictor=FakePredictor())) as client:     # a second start changes nothing
        assert client.get("/health").status_code == 200


def test_old_sqlite_database_is_upgraded(tmp_path):
    _check_upgrade(f"sqlite:///{(tmp_path / 'old.db').as_posix()}", {"image_dir": tmp_path / "img"})


@pytest.mark.skipif(not os.environ.get("TEST_DATABASE_URL"), reason="TEST_DATABASE_URL not set")
def test_old_postgres_database_is_upgraded(tmp_path):
    from app.db import normalize_url
    _check_upgrade(normalize_url(os.environ["TEST_DATABASE_URL"]), {"image_dir": tmp_path / "img"})
