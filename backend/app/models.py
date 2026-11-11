"""Database tables, following CP1 Table 4 (Explanation_Log and Clinic are added with their features)."""
from datetime import datetime, timezone

from sqlalchemy import JSON, Boolean, DateTime, Float, ForeignKey, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .db import Base


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def as_utc(dt: datetime) -> datetime:
    """SQLite returns times without a time zone; they are stored as UTC, so label them as UTC."""
    return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)


class User(Base):
    """Transactional. Account plus the consent states required by NFR4."""
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(primary_key=True)
    email: Mapped[str] = mapped_column(String(254), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(255))          # Argon2id, salted (FR11)
    consent_storage: Mapped[bool] = mapped_column(Boolean, default=False)
    consent_storage_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    consent_location: Mapped[bool] = mapped_column(Boolean, default=False)
    consent_location_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow)

    screenings: Mapped[list["Screening"]] = relationship(back_populates="user", cascade="all, delete-orphan",
                                                         passive_deletes=True)


class Condition(Base):
    """Master data. Reference content for FR8, seeded from app/data/conditions.json."""
    __tablename__ = "conditions"

    id: Mapped[str] = mapped_column(String(32), primary_key=True)    # same keys as the model classes
    name: Mapped[str] = mapped_column(String(100))
    category: Mapped[str] = mapped_column(String(100))
    typical_presentation: Mapped[str] = mapped_column(Text, default="")
    general_guidance: Mapped[str] = mapped_column(Text, default="")
    urgency_default: Mapped[str] = mapped_column(String(20))           # 'routine' or 'see_doctor'


class Screening(Base):
    """Transactional. One row per screening (FR7). Also the record of how the model behaves in use."""
    __tablename__ = "screenings"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    image_reference: Mapped[str | None] = mapped_column(String(255))   # None if the user did not consent to storage
    symptom_details: Mapped[dict | None] = mapped_column(JSON)         # FR2
    predicted_condition_id: Mapped[str] = mapped_column(ForeignKey("conditions.id"))
    confidence_value: Mapped[float] = mapped_column(Float)             # calibrated
    band: Mapped[str] = mapped_column(String(10))                      # high / moderate / refer
    capped: Mapped[bool] = mapped_column(Boolean, default=False)
    recommended_action: Mapped[str] = mapped_column(String(20))        # see_doctor / monitor
    probabilities: Mapped[dict] = mapped_column(JSON)
    model_version: Mapped[str] = mapped_column(String(50))
    model_band: Mapped[str | None] = mapped_column(String(10))           # band before the Claude check
    claude_check: Mapped[dict | None] = mapped_column(JSON)               # Claude's structured answer, or None
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, index=True)

    user: Mapped[User] = relationship(back_populates="screenings")
    condition: Mapped[Condition] = relationship()
