"""Lumis skin-condition predictor.

Runs the exported EfficientNet-B0 (ONNX) and turns its output into what the app shows:
a condition, a calibrated confidence and a band (high / moderate / refer).

Preprocessing reproduces training exactly (ml/03_train.ipynb), checked pixel for pixel in ml/09_export.ipynb:
  1. Decode to RGB. JPEG uses libjpeg-turbo with the fast integer DCT, which is what
     tf.io.decode_image uses by default. PNG and WebP are decoded by Pillow.
  2. Resize to 224 x 224 like tf.image.resize: bilinear, half-pixel centers, no antialiasing,
     aspect ratio NOT kept (training stretched every image to a square).
  3. Cast to uint8 (truncation), then to float32 in the 0-255 range. EfficientNet scales and
     normalizes inside the model, so nothing else is done here.
One deliberate difference from training: phone photos are turned upright using their EXIF
orientation tag, because phones often save the pixels sideways.

Output steps, decided in notebooks 04, 04b and 08:
  adjusted logits = logits + logit_adjust     (prior adjustment, training mix, tau 0.75)
  probabilities   = softmax(adjusted logits / temperature)
  band            = high if confidence >= high_from, moderate if >= refer_below, else refer
  scabies (any class in cap_at_moderate) is never shown as high: at most moderate.
"""
from __future__ import annotations

import hashlib
import io
import json
from dataclasses import asdict, dataclass, field
from pathlib import Path

import numpy as np
import simplejpeg
from PIL import Image, UnidentifiedImageError

MAX_PIXELS = 50_000_000          # about 8,000 x 6,000; larger uploads are refused
SUPPORTED_FORMATS = {"JPEG", "PNG", "WEBP"}


class UnsupportedImageError(ValueError):
    """The upload is not an image Lumis can read."""


# ---------------------------------------------------------------- preprocessing

def _apply_exif_orientation(rgb: np.ndarray, orientation: int) -> np.ndarray:
    """Same result as PIL.ImageOps.exif_transpose, on a numpy array."""
    if orientation == 2:
        return rgb[:, ::-1]
    if orientation == 3:
        return rgb[::-1, ::-1]
    if orientation == 4:
        return rgb[::-1]
    if orientation == 5:
        return rgb.transpose(1, 0, 2)
    if orientation == 6:
        return np.rot90(rgb, -1)
    if orientation == 7:
        return rgb.transpose(1, 0, 2)[::-1, ::-1]
    if orientation == 8:
        return np.rot90(rgb, 1)
    return rgb


def decode_image(data: bytes, apply_exif: bool = True) -> np.ndarray:
    """Bytes of a JPEG, PNG or WebP file -> uint8 array of shape (height, width, 3)."""
    try:
        im = Image.open(io.BytesIO(data))
        fmt = im.format
        if fmt not in SUPPORTED_FORMATS:
            raise UnsupportedImageError(f"Unsupported image format: {fmt}. Use JPEG, PNG or WebP.")
        if im.width * im.height > MAX_PIXELS:
            raise UnsupportedImageError("Image is too large.")
        orientation = im.getexif().get(0x0112, 1) if apply_exif else 1
        rgb = None
        if fmt == "JPEG":
            try:
                rgb = simplejpeg.decode_jpeg(data, colorspace="RGB", fastdct=True, fastupsample=False)
            except ValueError:
                rgb = None       # unusual JPEGs (for example CMYK): fall back to Pillow below
        if rgb is None:
            rgb = np.asarray(im.convert("RGB"))
    except UnsupportedImageError:
        raise
    except (UnidentifiedImageError, OSError, ValueError, Image.DecompressionBombError) as exc:
        raise UnsupportedImageError("The file could not be read as an image.") from exc
    return _apply_exif_orientation(rgb, orientation)


def resize_like_tf(img: np.ndarray, size: int) -> np.ndarray:
    """tf.image.resize(img, (size, size)) with its defaults: bilinear, half-pixel centers,
    no antialiasing. Returns float32."""
    h, w = img.shape[:2]

    def coords(n_in: int, n_out: int):
        src = (np.arange(n_out, dtype=np.float32) + 0.5) * np.float32(n_in / n_out) - 0.5
        lo = np.floor(src)
        frac = (src - lo).astype(np.float32)
        lo_i = np.clip(lo, 0, n_in - 1).astype(np.int64)
        hi_i = np.clip(lo + 1, 0, n_in - 1).astype(np.int64)
        return lo_i, hi_i, frac

    y0, y1, fy = coords(h, size)
    x0, x1, fx = coords(w, size)
    img = img.astype(np.float32)
    fx3, fy3 = fx[None, :, None], fy[:, None, None]
    top = img[y0][:, x0] * (1 - fx3) + img[y0][:, x1] * fx3
    bottom = img[y1][:, x0] * (1 - fx3) + img[y1][:, x1] * fx3
    return top * (1 - fy3) + bottom * fy3


def preprocess(data: bytes, size: int = 224, apply_exif: bool = True) -> np.ndarray:
    """Image file bytes -> float32 model input of shape (1, size, size, 3), values 0-255."""
    rgb = decode_image(data, apply_exif=apply_exif)
    resized = resize_like_tf(rgb, size).astype(np.uint8)       # truncation, as in training
    return resized.astype(np.float32)[None]


# ---------------------------------------------------------------- model output -> result

@dataclass(frozen=True)
class ModelConfig:
    model_version: str
    classes: list[str]
    img_size: int
    temperature: float
    logit_adjust: list[float]
    high_from: float
    refer_below: float
    cap_at_moderate: list[str] = field(default_factory=list)
    onnx_sha256: str | None = None
    model_file: str = "model.onnx"

    @classmethod
    def load(cls, path: str | Path) -> "ModelConfig":
        c = json.loads(Path(path).read_text())
        return cls(model_version=c["model_version"], classes=list(c["classes"]), img_size=int(c["img_size"]),
                   temperature=float(c["temperature"]), logit_adjust=[float(v) for v in c["logit_adjust"]],
                   high_from=float(c["bands"]["high_from"]), refer_below=float(c["bands"]["refer_below"]),
                   cap_at_moderate=list(c.get("cap_at_moderate", [])), onnx_sha256=c.get("onnx_sha256"),
                   model_file=c.get("model_file", "model.onnx"))


@dataclass(frozen=True)
class Prediction:
    condition: str              # most likely class (also given for 'refer', but the app shows it as inconclusive)
    confidence: float           # calibrated probability of that class, 0-1
    band: str                   # 'high' | 'moderate' | 'refer'
    probabilities: dict[str, float]
    capped: bool                # True if the scabies rule lowered the band from high to moderate
    model_version: str

    def to_dict(self) -> dict:
        return asdict(self)


def softmax(z: np.ndarray) -> np.ndarray:
    z = z - z.max(axis=-1, keepdims=True)
    e = np.exp(z)
    return e / e.sum(axis=-1, keepdims=True)


def postprocess(logits: np.ndarray, cfg: ModelConfig) -> Prediction:
    """Raw model logits for one image (shape (K,)) -> Prediction."""
    logits = np.asarray(logits, dtype=np.float64).reshape(-1)
    probs = softmax((logits + np.asarray(cfg.logit_adjust)) / cfg.temperature)
    i = int(probs.argmax())
    conf = float(probs[i])
    condition = cfg.classes[i]
    if conf >= cfg.high_from:
        band = "high"
    elif conf >= cfg.refer_below:
        band = "moderate"
    else:
        band = "refer"
    capped = band == "high" and condition in cfg.cap_at_moderate
    if capped:
        band = "moderate"
    return Prediction(condition=condition, confidence=round(conf, 4), band=band,
                      probabilities={c: round(float(p), 4) for c, p in zip(cfg.classes, probs)},
                      capped=capped, model_version=cfg.model_version)


# ---------------------------------------------------------------- the predictor

def sha256_of(path: str | Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


class LumisPredictor:
    """Load once at startup, then call predict() per upload. Safe to share across requests."""

    def __init__(self, model_path: str | Path, config_path: str | Path, verify_checksum: bool = True):
        import onnxruntime as ort

        self.config = ModelConfig.load(config_path)
        if verify_checksum and self.config.onnx_sha256:
            actual = sha256_of(model_path)
            if actual != self.config.onnx_sha256:
                raise RuntimeError(f"Model file does not match its config (sha256 {actual[:12]}..., "
                                   f"expected {self.config.onnx_sha256[:12]}...). Re-download both from Drive.")
        self.session = ort.InferenceSession(str(model_path), providers=["CPUExecutionProvider"])
        self.input_name = self.session.get_inputs()[0].name

    @classmethod
    def from_dir(cls, models_dir: str | Path, config_name: str = "lumis_model_config.json") -> "LumisPredictor":
        """Load the config in models_dir and the ONNX file it names."""
        models_dir = Path(models_dir)
        config_path = models_dir / config_name
        return cls(models_dir / ModelConfig.load(config_path).model_file, config_path)

    def logits(self, batch: np.ndarray) -> np.ndarray:
        return self.session.run(None, {self.input_name: batch.astype(np.float32)})[0]

    def predict(self, data: bytes) -> Prediction:
        x = preprocess(data, self.config.img_size)
        return postprocess(self.logits(x)[0], self.config)
