"""Where uploaded images are kept, only for users who consented to storage (NFR4, FR7).

Development: a local folder (backend/uploads, git-ignored).
Production (Cloud Run): a private Google Cloud Storage bucket, named in IMAGE_BUCKET. Cloud Run's own disk is
temporary and counts as memory, so nothing is written to it. Cloud Storage encrypts at rest by default.
Both classes have the same four methods, so the rest of the backend does not know which one is in use."""
import re
import uuid
from pathlib import Path
from typing import Protocol


def image_extension(data: bytes) -> str:
    if data[:3] == b"\xff\xd8\xff":
        return "jpg"
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        return "png"
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "webp"
    return "bin"


MEDIA_TYPES = {"jpg": "image/jpeg", "png": "image/png", "webp": "image/webp", "bin": "application/octet-stream"}


class LocalImageStorage:
    def __init__(self, root: Path):
        self.root = Path(root).resolve()
        self.root.mkdir(parents=True, exist_ok=True)

    def _path(self, reference: str) -> Path:
        path = (self.root / reference).resolve()
        if self.root not in path.parents:
            raise ValueError("Invalid image reference")
        return path

    def save(self, user_id: int, data: bytes) -> str:
        reference = f"u{user_id}/{uuid.uuid4().hex}.{image_extension(data)}"
        path = self._path(reference)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return reference

    def load(self, reference: str) -> bytes:
        return self._path(reference).read_bytes()

    def delete(self, reference: str) -> None:
        self._path(reference).unlink(missing_ok=True)

    @staticmethod
    def media_type(reference: str) -> str:
        return MEDIA_TYPES.get(reference.rsplit(".", 1)[-1], "application/octet-stream")


class ImageStorage(Protocol):
    def save(self, user_id: int, data: bytes) -> str: ...
    def load(self, reference: str) -> bytes: ...
    def delete(self, reference: str) -> None: ...
    def media_type(self, reference: str) -> str: ...


REFERENCE = re.compile(r"u\d+/[0-9a-f]{32}\.(jpg|png|webp|bin)")


class GCSImageStorage:
    """Photos as objects in one private bucket, named u<user id>/<random>.<type> like the local folder.
    On Cloud Run the client signs in as the service's own service account; no key file is needed."""

    def __init__(self, bucket_name: str, client=None):
        from google.api_core.exceptions import NotFound
        if client is None:
            from google.cloud import storage
            client = storage.Client()
        self._not_found = NotFound
        self.bucket_name = bucket_name
        self.bucket = client.bucket(bucket_name)

    def _blob(self, reference: str):
        if not REFERENCE.fullmatch(reference):
            raise ValueError("Invalid image reference")
        return self.bucket.blob(reference)

    def save(self, user_id: int, data: bytes) -> str:
        extension = image_extension(data)
        reference = f"u{int(user_id)}/{uuid.uuid4().hex}.{extension}"
        # if_generation_match=0: only create, never overwrite; it also lets the library retry safely
        self._blob(reference).upload_from_string(data, content_type=MEDIA_TYPES[extension], if_generation_match=0)
        return reference

    def load(self, reference: str) -> bytes:
        try:
            return self._blob(reference).download_as_bytes()
        except self._not_found as exc:
            raise FileNotFoundError(reference) from exc

    def delete(self, reference: str) -> None:
        try:
            self._blob(reference).delete()
        except self._not_found:
            pass                                    # already gone: same as the local version

    @staticmethod
    def media_type(reference: str) -> str:
        return MEDIA_TYPES.get(reference.rsplit(".", 1)[-1], "application/octet-stream")


def make_storage(settings) -> ImageStorage:
    """The bucket if IMAGE_BUCKET is set (required in production), otherwise the local folder."""
    if settings.image_bucket:
        return GCSImageStorage(settings.image_bucket)
    return LocalImageStorage(settings.image_dir)
