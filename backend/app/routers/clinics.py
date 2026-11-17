"""Dermatology clinic directory (FR6): every listed place, or the nearest ones to a location.

No login is needed: the list is public reference information. A location is used only to sort the list and is
never stored or logged (see app/clinics.py)."""
from fastapi import APIRouter, Query, Request

from ..clinics import COVERAGE_KM
from ..schemas import ClinicListOut, ClinicType, NearbyIn, NearbyOut

router = APIRouter(prefix="/clinics", tags=["clinics"])


@router.get("", response_model=ClinicListOut)
def all_clinics(request: Request, type: list[ClinicType] | None = Query(None)):
    """Every place in the directory, A to Z. Use this when the person has not turned on location."""
    directory = request.app.state.clinics
    return {"directory": directory.meta, "clinics": directory.all(type)}


@router.post("/nearby", response_model=NearbyOut)
def nearby_clinics(body: NearbyIn, request: Request):
    """The nearest places to a location, closest first, with the straight-line distance.

    POST, not GET, so the location travels in the request body and never appears in request logs. It is not
    stored. Places without a map pin are not in this list (they are in GET /clinics)."""
    directory = request.app.state.clinics
    found = directory.nearest(body.lat, body.lon, body.limit, body.types)
    return {"directory": directory.meta, "clinics": found,
            "outside_coverage": not found or found[0]["distance_km"] > COVERAGE_KM}
