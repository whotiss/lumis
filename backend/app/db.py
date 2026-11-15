"""Database connection. SQLite for local development and tests, PostgreSQL in production."""
from sqlalchemy import create_engine, event
from sqlalchemy.engine import Engine
from sqlalchemy.orm import DeclarativeBase


class Base(DeclarativeBase):
    pass


def normalize_url(url: str) -> str:
    """Database hosts hand out URLs starting with postgresql:// (or postgres://). SQLAlchemy would then look for
    the older psycopg2 driver, which Lumis does not install, so point those URLs at psycopg 3."""
    for prefix in ("postgresql://", "postgres://"):
        if url.startswith(prefix):
            return "postgresql+psycopg://" + url[len(prefix):]
    return url


def make_engine(url: str) -> Engine:
    url = normalize_url(url)
    if url.startswith("sqlite"):
        engine = create_engine(url, connect_args={"check_same_thread": False})

        @event.listens_for(engine, "connect")
        def _enable_foreign_keys(dbapi_conn, _):          # SQLite ignores foreign keys unless asked
            dbapi_conn.execute("PRAGMA foreign_keys=ON")

        return engine
    # PostgreSQL. A hosted database that sleeps when idle closes its connections, so each one is tested before
    # use (pool_pre_ping) and replaced after 5 minutes. Few connections: free database plans have low limits.
    # prepare_threshold None: no server-side prepared statements, so a pooled connection address also works.
    return create_engine(url, pool_pre_ping=True, pool_recycle=300, pool_size=3, max_overflow=5,
                         connect_args={"prepare_threshold": None, "connect_timeout": 15})
