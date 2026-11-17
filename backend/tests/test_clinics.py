"""Clinic directory (FR6): the data file is sound, distances are right, and a location is never kept."""
import json
import logging

import pytest
from fastapi.testclient import TestClient

from app.clinics import CLINICS_FILE, COVERAGE_KM, Directory, check, distance_km
from app.config import Settings
from app.main import create_app

from .test_api import FakePredictor

SUNWAY_UNIVERSITY = (3.0672, 101.6037)
KLCC = (3.1579, 101.7116)
PENANG = (5.4141, 100.3288)


@pytest.fixture
def client(tmp_path):
    settings = Settings(database_url=f"sqlite:///{(tmp_path / 'c.db').as_posix()}", image_dir=tmp_path / "img",
                        jwt_secret="test-secret-at-least-32-characters-long")
    with TestClient(create_app(settings, predictor=FakePredictor())) as c:
        yield c


# ---------------------------------------------------------------- the data file

def test_data_file_passes_every_check():
    doc = json.loads(CLINICS_FILE.read_text(encoding="utf-8"))
    assert check(doc["clinics"]) == []
    assert len(doc["clinics"]) >= 70
    assert "OpenStreetMap" in doc["attribution"] and doc["checked"]


def test_every_place_has_a_dermatologist_source():
    for c in Directory.load().clinics:
        assert all(u.startswith("https://www.dermatology.org.my/") for u in c["dermatologist_source"]), c["id"]


def test_all_four_kinds_of_place_are_covered():
    kinds = {c["type"] for c in Directory.load().clinics}
    assert kinds == {"government_hospital", "university_hospital", "private_hospital", "specialist_clinic"}


@pytest.mark.parametrize("change,problem", [
    ({"type": "spa"}, "unknown type"),
    ({"dermatologist_source": []}, "no source"),
    ({"lat": None}, "both"),
    ({"lat": 1.29, "lon": 103.85}, "outside the Klang Valley"),          # Singapore: a lookup mistake
    ({"location_precision": None}, "location_precision"),
    ({"address": ""}, "no address"),
])
def test_check_catches_bad_entries(change, problem):
    good = Directory.load().clinics[0]
    assert check([good]) == []
    assert any(problem in p for p in check([{**good, **change}]))


def test_check_catches_duplicate_ids():
    good = Directory.load().clinics[0]
    assert "duplicate ids" in check([good, dict(good)])


def test_a_bad_file_stops_the_start(tmp_path):
    doc = json.loads(CLINICS_FILE.read_text(encoding="utf-8"))
    doc["clinics"][0]["type"] = "spa"
    bad = tmp_path / "clinics.json"
    bad.write_text(json.dumps(doc), encoding="utf-8")
    with pytest.raises(RuntimeError, match="unknown type"):
        Directory.load(bad)


# ---------------------------------------------------------------- distances

def test_distance_matches_known_values():
    assert distance_km(*SUNWAY_UNIVERSITY, *SUNWAY_UNIVERSITY) == 0
    assert distance_km(*SUNWAY_UNIVERSITY, *KLCC) == pytest.approx(15.6, abs=0.3)    # about 15-16 km apart
    assert distance_km(0, 0, 0, 1) == pytest.approx(111.2, abs=0.1)                  # one degree at the equator


def test_nearest_to_sunway_university():
    found = Directory.load().nearest(*SUNWAY_UNIVERSITY, limit=3)
    assert [c["id"] for c in found] == ["sunway-mc", "sjmc", "ranjit-ss15"]
    assert [c["distance_km"] for c in found] == sorted(c["distance_km"] for c in found)
    assert found[0]["distance_km"] < 1


def test_places_without_a_pin_are_listed_but_not_sorted():
    d = Directory.load()
    unpinned = [c["id"] for c in d.clinics if c["lat"] is None]
    assert unpinned                                         # at least one (its address could not be placed)
    assert set(unpinned) <= {c["id"] for c in d.all()}
    assert not set(unpinned) & {c["id"] for c in d.nearest(*KLCC, limit=100)}


# ---------------------------------------------------------------- the API

def test_list_all_and_filter_by_type(client):
    r = client.get("/clinics").json()
    assert len(r["clinics"]) >= 70 and r["directory"]["attribution"]
    names = [c["name"].lower() for c in r["clinics"]]
    assert names == sorted(names)
    gov = client.get("/clinics", params={"type": "government_hospital"}).json()["clinics"]
    assert gov and all(c["type"] == "government_hospital" for c in gov)
    assert all("referral" in c["access"] for c in gov)
    assert client.get("/clinics", params={"type": "spa"}).status_code == 422


def test_nearby_from_sunway(client):
    r = client.post("/clinics/nearby", json={"lat": SUNWAY_UNIVERSITY[0], "lon": SUNWAY_UNIVERSITY[1], "limit": 5})
    body = r.json()
    assert r.status_code == 200 and body["outside_coverage"] is False
    assert len(body["clinics"]) == 5 and body["clinics"][0]["id"] == "sunway-mc"
    assert all(c["distance_km"] is not None for c in body["clinics"])


def test_nearby_only_one_kind(client):
    r = client.post("/clinics/nearby", json={"lat": KLCC[0], "lon": KLCC[1], "types": ["specialist_clinic"]}).json()
    assert r["clinics"] and all(c["type"] == "specialist_clinic" for c in r["clinics"])


def test_nearby_far_away_says_outside_coverage(client):
    r = client.post("/clinics/nearby", json={"lat": PENANG[0], "lon": PENANG[1]}).json()
    assert r["outside_coverage"] is True and r["clinics"][0]["distance_km"] > COVERAGE_KM


@pytest.mark.parametrize("body", [{"lat": 91, "lon": 101}, {"lat": 3, "lon": 181}, {"lat": 3, "lon": 101, "limit": 0},
                                  {"lat": 3, "lon": 101, "limit": 51}, {"lon": 101}])
def test_nearby_rejects_bad_input(client, body):
    assert client.post("/clinics/nearby", json=body).status_code == 422


def test_no_login_needed(client):
    assert client.get("/clinics").status_code == 200
    assert client.post("/clinics/nearby", json={"lat": 3.1, "lon": 101.6}).status_code == 200


def test_location_is_not_kept_or_logged(client, caplog, tmp_path):
    """The consent text promises the location is used only to sort clinics and is not stored."""
    lat, lon = 3.0672123, 101.6037456                         # unusual digits, easy to search for
    with caplog.at_level(logging.DEBUG):
        r = client.post("/clinics/nearby", json={"lat": lat, "lon": lon})
    assert r.status_code == 200
    assert "3.0672123" not in caplog.text and "101.6037456" not in caplog.text
    assert "3.0672123" not in r.text                            # the answer does not echo it back either
    db = (tmp_path / "c.db").read_bytes()
    assert b"3.0672123" not in db and b"101.6037456" not in db
