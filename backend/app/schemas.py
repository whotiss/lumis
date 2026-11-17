"""Request and response shapes (the contract the Flutter app is built against)."""
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, EmailStr, Field


class RegisterIn(BaseModel):
    # Example shown on the /docs page, so "Try it out" then "Execute" works as it is
    model_config = ConfigDict(json_schema_extra={"example": {
        "email": "demo@lumis.app", "password": "lumis-demo-123", "accept_consent_version": "2026-11-17",
        "confirm_adult": True, "consent_storage": True, "consent_location": False}})

    email: EmailStr
    password: str = Field(min_length=8, max_length=128)
    accept_consent_version: str = Field(description="The version from GET /consent that the person ticked")
    confirm_adult: bool = Field(description="The required 'I am 18 or older' box")
    consent_storage: bool = False
    consent_location: bool = False


class TokenOut(BaseModel):
    access_token: str
    token_type: str = "bearer"


class UserOut(BaseModel):
    id: int
    email: str
    consent_storage: bool
    consent_location: bool
    consent_version: str | None              # what the person agreed to; compare with GET /consent
    consent_current: bool                    # False: show the consent screen again before the next screening
    created_at: datetime


class AcceptConsentIn(BaseModel):
    version: str
    confirm_adult: bool


class ConsentItemOut(BaseModel):
    id: str
    required: bool
    label: str


class ConsentSectionOut(BaseModel):
    heading: str
    body: str


class ConsentOut(BaseModel):
    version: str
    language: Literal["en", "ms"]
    title: str
    sections: list[ConsentSectionOut]
    items: list[ConsentItemOut]


class ConsentIn(BaseModel):
    consent_storage: bool | None = None
    consent_location: bool | None = None


class SymptomDetails(BaseModel):
    """FR2: optional, structured (no free text, so nothing personal can be typed in)."""
    duration: Literal["under_1_week", "1_to_4_weeks", "over_1_month"] | None = None
    itchy: bool | None = None
    changing: bool | None = None


class ConditionRef(BaseModel):
    id: str
    name: str


class ScreeningOut(BaseModel):
    id: int
    created_at: datetime
    band: Literal["high", "moderate", "refer"]
    band_label: str
    condition: ConditionRef | None          # None when inconclusive: no condition is named
    confidence: float | None                # calibrated; None when inconclusive
    headline: str
    advice: str
    recommended_action: Literal["see_doctor", "monitor"]
    show_clinics: bool
    disclaimer: str
    symptom_details: SymptomDetails | None
    image_available: bool
    model_version: str


class ConditionOut(BaseModel):
    id: str
    name: str
    category: str
    typical_presentation: str
    general_guidance: str
    urgency_default: str


class ModelInfoOut(BaseModel):
    model_version: str
    classes: list[str]
    bands: dict
    test_results: dict | None
