"""Tests for the parts that only matter on the server: production settings, the PostgreSQL connection and
photo storage in a Cloud Storage bucket (with a stand-in bucket, no network).

The last tests run the whole API against a real PostgreSQL database. They are skipped unless
TEST_DATABASE_URL is set, for example:  TEST_DATABASE_URL=postgresql://user:password@localhost/lumis_test
(use an empty test database: the tests create and delete rows in it)."""
import io
import os

import numpy as np
import pytest
from fastapi.testclient import TestClient
from PIL import Image

from app.config import DEV_SECRET, Settings
from app.db import make_engine, normalize_url
from app.main import create_app
from app.storage import GCSImageStorage, LocalImageStorage, make_storage

from .test_api import FakePredictor

SECRET = "test-secret-at-least-32-characters-long"


# ---------------------------------------------------------------- production settings

def test_production_refuses_development_defaults(tmp_path):
    good = dict(environment="production", jwt_secret=SECRET, database_url="postgresql://u:p@host/db",
                image_bucket="lumis-uploads")
    good["_env_file"] = None
    Settings(**good).check()                                                   # complete: accepted
    for change, message in [({"jwt_secret": DEV_SECRET}, "JWT_SECRET"), ({"jwt_secret": "short"}, "JWT_SECRET"),
                            ({"database_url": f"sqlite:///{tmp_path}/x.db"}, "PostgreSQL"),
                            ({"image_bucket": None}, "IMAGE_BUCKET")]:
        with pytest.raises(RuntimeError, match=message):
            Settings(**{**good, **change}).check()
    Settings(environment="development", _env_file=None).check()                # development: defaults are fine


def test_secrets_lose_stray_whitespace(monkeypatch):
    monkeypatch.setenv("JWT_SECRET", SECRET + "\r\n")                           # a newline added when the secret was saved
    monkeypatch.setenv("DATABASE_URL", " postgresql://u:p@host/db\n")
    monkeypatch.setenv("ANTHROPIC_API_KEY", "key-value\n")
    s = Settings(_env_file=None)
    assert s.jwt_secret == SECRET and s.database_url == "postgresql://u:p@host/db" and s.anthropic_api_key == "key-value"


def test_database_urls_use_psycopg3():
    assert normalize_url("postgresql://u:p@h/db?sslmode=require") == "postgresql+psycopg://u:p@h/db?sslmode=require"
    assert normalize_url("postgres://u:p@h/db") == "postgresql+psycopg://u:p@h/db"
    assert normalize_url("postgresql+psycopg://u:p@h/db") == "postgresql+psycopg://u:p@h/db"
    assert normalize_url("sqlite:///x.db") == "sqlite:///x.db"
    engine = make_engine("postgresql://u:p@localhost:1/db")                    # no connection is made yet
    assert engine.dialect.driver == "psycopg" and engine.pool._pre_ping
    engine.dispose()


# ---------------------------------------------------------------- photo storage in a bucket

try:
    from google.api_core import exceptions as gcs_exceptions
except ImportError:                                  # pip install -r requirements.txt brings it in
    gcs_exceptions = None
needs_gcs_library = pytest.mark.skipif(gcs_exceptions is None, reason="google-cloud-storage is not installed")


class FakeBlob:
    def __init__(self, objects, name):
        self.objects, self.name = objects, name

    def upload_from_string(self, data, content_type=None, if_generation_match=None):
        assert if_generation_match == 0                                        # create only, never overwrite
        if self.name in self.objects:
            raise gcs_exceptions.PreconditionFailed("exists")
        self.objects[self.name] = (bytes(data), content_type)

    def download_as_bytes(self):
        if self.name not in self.objects:
            raise gcs_exceptions.NotFound(self.name)
        return self.objects[self.name][0]

    def delete(self):
        if self.name not in self.objects:
            raise gcs_exceptions.NotFound(self.name)
        del self.objects[self.name]


class FakeClient:
    def __init__(self):
        self.buckets = {}

    def bucket(self, name):
        objects = self.buckets.setdefault(name, {})

        class Bucket:
            def blob(self, blob_name):
                return FakeBlob(objects, blob_name)
        return Bucket()


def jpeg(seed=0, size=(300, 400)):
    b = io.BytesIO()
    Image.fromarray(np.random.default_rng(seed).integers(0, 255, (*size, 3), dtype=np.uint8)).save(b, "JPEG")
    return b.getvalue()


@needs_gcs_library
def test_bucket_storage_save_load_delete():
    client = FakeClient()
    store = GCSImageStorage("lumis-uploads", client=client)
    data = jpeg()
    ref = store.save(7, data)
    assert ref.startswith("u7/") and ref.endswith(".jpg") and store.media_type(ref) == "image/jpeg"
    assert client.buckets["lumis-uploads"][ref] == (data, "image/jpeg")
    assert store.load(ref) == data
    assert store.save(7, data) != ref                                          # every photo gets its own name
    store.delete(ref)
    store.delete(ref)                                                          # deleting twice is not an error
    with pytest.raises(FileNotFoundError):
        store.load(ref)


@needs_gcs_library
@pytest.mark.parametrize("bad", ["../secrets", "u1/../../x.jpg", "/etc/passwd", "u1/abc.jpg", "other/" + "a" * 32 + ".jpg", ""])
def test_bucket_storage_rejects_strange_references(bad):
    store = GCSImageStorage("lumis-uploads", client=FakeClient())
    for call in (store.load, store.delete):
        with pytest.raises(ValueError):
            call(bad)


@needs_gcs_library
def test_storage_is_chosen_by_settings(tmp_path, monkeypatch):
    assert isinstance(make_storage(Settings(image_dir=tmp_path / "img", _env_file=None)), LocalImageStorage)
    monkeypatch.setattr("app.storage.GCSImageStorage.__init__",
                        lambda self, bucket_name, client=None: setattr(self, "bucket_name", bucket_name))
    store = make_storage(Settings(image_bucket="lumis-uploads", _env_file=None))
    assert isinstance(store, GCSImageStorage) and store.bucket_name == "lumis-uploads"


@needs_gcs_library
def test_api_with_bucket_storage(tmp_path):
    """Whole screening flow with photos kept in the (stand-in) bucket: store, read back, delete, delete account."""
    client_gcs = FakeClient()
    settings = Settings(database_url=f"sqlite:///{(tmp_path / 'b.db').as_posix()}", jwt_secret=SECRET,
                        image_dir=tmp_path / "img")
    app = create_app(settings, predictor=FakePredictor())
    with TestClient(app) as client:
        app.state.storage = GCSImageStorage("lumis-uploads", client=client_gcs)
        objects = client_gcs.buckets["lumis-uploads"]
        r = client.post("/auth/register", json={"email": "a@example.com", "password": "correct horse", "consent_storage": True})
        h = {"Authorization": f"Bearer {r.json()['access_token']}"}
        data = jpeg(1)
        ids = [client.post("/screenings", headers=h, files={"image": ("p.jpg", data, "image/jpeg")}).json()["id"] for _ in range(2)]
        assert len(objects) == 2
        assert client.get(f"/screenings/{ids[0]}/image", headers=h).content == data
        assert client.delete(f"/screenings/{ids[0]}", headers=h).status_code == 204 and len(objects) == 1
        objects.clear()                                                        # the photo vanished from the bucket
        assert client.get(f"/screenings/{ids[1]}/image", headers=h).status_code == 404
        assert client.delete("/me", headers=h).status_code == 204              # still deletes the account cleanly


# ---------------------------------------------------------------- the real PostgreSQL path

PG_URL = os.environ.get("TEST_DATABASE_URL")
needs_postgres = pytest.mark.skipif(not PG_URL or gcs_exceptions is None, reason="TEST_DATABASE_URL not set")


@pytest.fixture
def pg_client(tmp_path):
    from sqlalchemy import text
    engine = make_engine(PG_URL)
    with engine.begin() as conn:                                               # start from empty tables
        for table in ("screenings", "users", "conditions"):
            conn.execute(text(f"DROP TABLE IF EXISTS {table} CASCADE"))
    engine.dispose()
    settings = Settings(environment="production", database_url=PG_URL, jwt_secret=SECRET, image_bucket="lumis-uploads")
    app = create_app(settings, predictor=FakePredictor())
    gcs = FakeClient()
    with TestClient(app) as client:
        app.state.storage = GCSImageStorage("lumis-uploads", client=gcs)
        yield client, gcs.buckets["lumis-uploads"]


@pytest.fixture(autouse=True)
def _no_real_bucket(monkeypatch):
    """create_app builds the real bucket client in production; tests must never reach the network."""
    if gcs_exceptions is not None:
        monkeypatch.setattr("app.main.make_storage", lambda settings: LocalImageStorage(settings.image_dir)
                            if not settings.image_bucket else GCSImageStorage(settings.image_bucket, client=FakeClient()))


@needs_postgres
def test_postgres_full_flow(pg_client):
    client, objects = pg_client
    assert client.get("/health").json()["status"] == "ok"
    assert len(client.get("/conditions").json()) == 5
    r = client.post("/auth/register", json={"email": "Pg@Example.com", "password": "correct horse", "consent_storage": True})
    assert r.status_code == 201
    h = {"Authorization": f"Bearer {r.json()['access_token']}"}
    assert client.post("/auth/register", json={"email": "pg@example.com", "password": "another one"}).status_code == 409
    assert client.post("/auth/login", data={"username": "pg@example.com", "password": "correct horse"}).status_code == 200
    data = jpeg(2)
    s = client.post("/screenings", headers=h, files={"image": ("p.jpg", data, "image/jpeg")},
                    data={"duration": "under_1_week", "itchy": "true"})
    assert s.status_code == 201, s.text
    body = s.json()
    assert body["band"] == "high" and body["symptom_details"] == {"duration": "under_1_week", "itchy": True, "changing": None}
    assert body["created_at"].endswith(("Z", "+00:00"))                        # times come back as UTC
    history = client.get("/screenings", headers=h).json()
    assert [x["id"] for x in history] == [body["id"]] and len(objects) == 1
    assert client.get(f"/screenings/{body['id']}/image", headers=h).content == data
    me = client.patch("/me/consent", headers=h, json={"consent_location": True}).json()
    assert me["consent_location"] is True
    assert client.delete("/me", headers=h).status_code == 204 and not objects   # account, screenings and photos gone
    assert client.get("/me", headers=h).status_code == 401


@needs_postgres
def test_postgres_restart_keeps_data(pg_client):
    """A second start against the same database (a new server instance) must not wipe or break anything."""
    client, _ = pg_client
    r = client.post("/auth/register", json={"email": "stay@example.com", "password": "correct horse"})
    h = {"Authorization": f"Bearer {r.json()['access_token']}"}
    settings = Settings(environment="production", database_url=PG_URL, jwt_secret=SECRET, image_bucket="lumis-uploads")
    with TestClient(create_app(settings, predictor=FakePredictor())) as second:
        assert second.get("/me", headers=h).json()["email"] == "stay@example.com"
        assert len(second.get("/conditions").json()) == 5
