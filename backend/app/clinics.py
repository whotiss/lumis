"""Dermatology clinic directory for the Klang Valley (FR6).

The list is reference data, not user data: it lives in data/clinics.json (versioned in git, each entry with its
sources) and is read once at startup. Nothing about the person asking is stored. A location sent to
POST /clinics/nearby is used to sort this list and then forgotten: it is not saved, and it is sent in the request
body so it does not appear in server or Cloud Run request logs (which record the address, including any query
string, but not the body).

How the list was made (data/clinics.json says the same, with the date):
  - A place is listed when at least one dermatologist in the Persatuan Dermatologi Malaysia directory names it as
    where they practise. Every entry links to those directory pages. Aesthetic clinics run by doctors who are not
    dermatologists are left out on purpose: Lumis tells people to see a dermatologist.
  - Map positions come from OpenStreetMap. location_precision says how exact a pin is: "building" (the place
    itself), "street" (the street it is on) or "area" (the neighbourhood or complex). A place without a usable
    position has no pin and is left out of distance sorting, but is still in the full list.
"""
from __future__ import annotations

import json
import math
from dataclasses import dataclass
from pathlib import Path

CLINICS_FILE = Path(__file__).parent / "data" / "clinics.json"
TYPES = ("government_hospital", "university_hospital", "private_hospital", "specialist_clinic")
PRECISIONS = ("building", "street", "area")
# Roughly the Klang Valley plus a margin. A pin outside it is a lookup mistake.
BOUNDS = {"lat": (2.80, 3.40), "lon": (101.30, 101.90)}
# If the nearest listed place is further than this, the person is probably outside the area the list covers.
COVERAGE_KM = 40.0
EARTH_RADIUS_KM = 6371.0


def distance_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Straight-line (great-circle) distance. Not the driving distance, and the app says so."""
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = p2 - p1, math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * EARTH_RADIUS_KM * math.asin(math.sqrt(a))


@dataclass(frozen=True)
class Directory:
    meta: dict
    clinics: list[dict]

    @classmethod
    def load(cls, path: Path = CLINICS_FILE) -> "Directory":
        doc = json.loads(path.read_text(encoding="utf-8"))
        clinics = doc.pop("clinics")
        problems = check(clinics)
        if problems:
            raise RuntimeError(f"{path.name} has problems: " + "; ".join(problems))
        return cls(meta=doc, clinics=sorted(clinics, key=lambda c: c["name"].lower()))

    def all(self, types: list[str] | None = None) -> list[dict]:
        return [c for c in self.clinics if not types or c["type"] in types]

    def nearest(self, lat: float, lon: float, limit: int = 10, types: list[str] | None = None) -> list[dict]:
        located = [c for c in self.all(types) if c["lat"] is not None]
        ranked = sorted(located, key=lambda c: distance_km(lat, lon, c["lat"], c["lon"]))
        return [{**c, "distance_km": round(distance_km(lat, lon, c["lat"], c["lon"]), 1)} for c in ranked[:limit]]


def check(clinics: list[dict]) -> list[str]:
    """Everything the app relies on. Run at startup and by the tests, so a bad edit never reaches users."""
    problems = []
    ids = [c.get("id") for c in clinics]
    if len(ids) != len(set(ids)):
        problems.append("duplicate ids")
    for c in clinics:
        name = c.get("id", "?")
        for field in ("id", "name", "type", "city", "address", "access"):
            if not c.get(field):
                problems.append(f"{name}: no {field}")
        if c.get("type") not in TYPES:
            problems.append(f"{name}: unknown type {c.get('type')!r}")
        if not c.get("dermatologist_source"):
            problems.append(f"{name}: no source showing a dermatologist practises there")
        has_lat, has_lon = c.get("lat") is not None, c.get("lon") is not None
        if has_lat != has_lon:
            problems.append(f"{name}: lat and lon must both be given or both be empty")
        if has_lat:
            if not (BOUNDS["lat"][0] <= c["lat"] <= BOUNDS["lat"][1] and BOUNDS["lon"][0] <= c["lon"] <= BOUNDS["lon"][1]):
                problems.append(f"{name}: pin outside the Klang Valley")
            if c.get("location_precision") not in PRECISIONS or not c.get("location_source"):
                problems.append(f"{name}: a pin needs location_precision and location_source")
    return problems
