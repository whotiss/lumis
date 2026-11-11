"""Where uploaded images are kept, only for users who consented to storage (NFR4, FR7).

Development: a local folder (backend/uploads, git-ignored). Production on Cloud Run will swap in a
Google Cloud Storage version with the same three methods (GCS encrypts at rest by default)."""
import uuid
from pathlib import Path


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
