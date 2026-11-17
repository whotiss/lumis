"""Database connection. SQLite for local development and tests, PostgreSQL in production."""
from sqlalchemy import create_engine, event, inspect, text
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


def add_missing_columns(engine: Engine) -> list[str]:
    """Bring an existing database up to date when a release adds new columns (create_all only makes new tables).
    Only nullable columns are added, so existing rows stay valid; returns what was added, for the log."""
    added = []
    existing_tables = set(inspect(engine).get_table_names())
    with engine.begin() as conn:
        for table in Base.metadata.sorted_tables:
            if table.name not in existing_tables:
                continue
            have = {c["name"] for c in inspect(conn).get_columns(table.name)}
            for column in table.columns:
                if column.name in have:
                    continue
                if not column.nullable:
                    raise RuntimeError(f"The database needs a new required column {table.name}.{column.name}; "
                                       "add it by hand or start from an empty database.")
                col_type = column.type.compile(dialect=engine.dialect)
                conn.execute(text(f'ALTER TABLE "{table.name}" ADD COLUMN "{column.name}" {col_type}'))
                added.append(f"{table.name}.{column.name}")
    return added
