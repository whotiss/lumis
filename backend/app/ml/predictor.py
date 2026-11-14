"""Lumis skin-condition predictor.

Runs the exported model (ONNX) and turns its output into what the app shows:
a condition, a calibrated confidence and a band (high / moderate / refer).

Two model formats, chosen by the config file (settings MODEL_CONFIG):
  v3 (current, ml/19_final_v3.ipynb): MedSigLIP image encoder (ONNX) -> 1152-number embedding -> small
     classifier (scaler, PCA 256, logistic regression; models/lumis_head_v3.npz) -> logits.
     Preprocessing as in notebook 19: Pillow decode, EXIF upright, RGB, resize to 448 x 448 with Pillow
     bicubic (aspect ratio not kept), scale to 0-1, normalize with mean 0.5 / std 0.5, channels first.
     Notebook 19 checked that this gives the same prediction as the training pipeline (64 of 64 photos).
     Photo check energy is taken on the calibrated logits, (logits + logit_adjust) / temperature.
  v1 (EfficientNet-B0, kept for comparison): described below.

v1 details:

Preprocessing reproduces training exactly (ml/03_train.ipynb), checked pixel for pixel in ml/09_export.ipynb:
  1. Decode to RGB. JPEG uses libjpeg-turbo with the fast integer DCT, which is what
     tf.io.decode_image uses by default. PNG and WebP are decoded by Pillow.
  2. Resize to 224 x 224 like tf.image.resize: bilinear, half-pixel centers, no antialiasing,
     aspect ratio NOT kept (training stretched every image to a square).
  3. Cast to uint8 (truncation), then to float32 in the 0-255 range. EfficientNet scales and
     normalizes inside the model, so nothing else is done here.
One deliberate difference from training: phone photos are turned upright using their EXIF
orientation tag, because phones often save the pixels sideways.

Photo check (notebook 10), before any result is shown:
  no_skin           too few skin-colored pixels (the notebook 06 rule: YCbCr Cr 130-190, Cb 70-130)
  nothing_detected  the photo is unlike any of the training photos (energy score above the threshold)
Thresholds live in models/photo_check.json. Without that file every photo passes.

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
import logging
import time
from dataclasses import asdict, dataclass, field, replace
from pathlib import Path

import numpy as np
import simplejpeg
from PIL import Image, ImageOps, UnidentifiedImageError

log = logging.getLogger("lumis.predictor")

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


def to_model_input(rgb: np.ndarray, size: int = 224) -> np.ndarray:
    """Decoded RGB array -> float32 model input of shape (1, size, size, 3), values 0-255."""
    resized = resize_like_tf(rgb, size).astype(np.uint8)       # truncation, as in training
    return resized.astype(np.float32)[None]


def preprocess(data: bytes, size: int = 224, apply_exif: bool = True) -> np.ndarray:
    """Image file bytes -> float32 model input of shape (1, size, size, 3), values 0-255."""
    return to_model_input(decode_image(data, apply_exif=apply_exif), size)


def open_image(data: bytes) -> Image.Image:
    """v3: bytes of a JPEG, PNG or WebP file -> upright RGB Pillow image, exactly as notebooks 16 and 19 opened
    photos: ImageOps.exif_transpose(Image.open(path)).convert('RGB')."""
    try:
        im = Image.open(io.BytesIO(data))
        if im.format not in SUPPORTED_FORMATS:
            raise UnsupportedImageError(f"Unsupported image format: {im.format}. Use JPEG, PNG or WebP.")
        if im.width * im.height > MAX_PIXELS:
            raise UnsupportedImageError("Image is too large.")
        return ImageOps.exif_transpose(im).convert("RGB")
    except UnsupportedImageError:
        raise
    except (UnidentifiedImageError, OSError, ValueError, Image.DecompressionBombError) as exc:
        raise UnsupportedImageError("The file could not be read as an image.") from exc


def to_encoder_input(img: Image.Image, pre: dict) -> np.ndarray:
    """v3: upright RGB image -> float32 encoder input of shape (1, 3, H, W), the preprocess_np function of
    notebook 19: Pillow resize (bicubic, resample 3), scale by 1/255, normalize, channels first."""
    h, w = pre["size"]
    a = np.asarray(img.resize((w, h), resample=pre["resample"]), dtype=np.float32) * np.float32(pre["rescale_factor"])
    a = (a - np.array(pre["image_mean"], np.float32)) / np.array(pre["image_std"], np.float32)
    return a.transpose(2, 0, 1)[None].astype(np.float32)


class LinearHead:
    """v3 classifier on top of the encoder: StandardScaler -> PCA -> logistic regression, from the arrays that
    notebook 19 saved (and checked against scikit-learn: largest logit difference 1.7e-6). Gives raw logits;
    the prior adjustment and temperature are applied in postprocess(), as for v1."""

    def __init__(self, path: str | Path):
        with np.load(path) as h:
            self.scaler_mean, self.scaler_scale = h["scaler_mean"], h["scaler_scale"]
            self.pca_mean, self.pca_components = h["pca_mean"], h["pca_components"]
            self.coef, self.intercept = h["coef"], h["intercept"]

    @property
    def embedding_dim(self) -> int:
        return int(self.scaler_mean.shape[0])

    def logits(self, embeddings: np.ndarray) -> np.ndarray:
        z = ((embeddings - self.scaler_mean) / self.scaler_scale - self.pca_mean) @ self.pca_components.T
        return z @ self.coef.T + self.intercept


# ---------------------------------------------------------------- photo check

def skin_fraction(rgb: np.ndarray) -> float:
    """Share of skin-colored pixels, the rule from notebook 06: on a 128 x 128 copy, YCbCr chroma
    Cr 130-190 and Cb 70-130. Deliberately wide so red rashes and darker skin count as skin."""
    small = Image.fromarray(np.ascontiguousarray(rgb)).resize((128, 128)).convert("YCbCr")
    ycc = np.asarray(small, dtype=np.int16)
    cb, cr = ycc[..., 1], ycc[..., 2]
    return float(((cr >= 130) & (cr <= 190) & (cb >= 70) & (cb <= 130)).mean())


def energy_score(logits: np.ndarray) -> float:
    """Energy of the raw logits, -logsumexp (Liu et al., 2020). Photos like the training photos get low
    (more negative) energy; photos unlike anything the model was trained on get higher energy."""
    z = np.asarray(logits, dtype=np.float64).reshape(-1)
    m = z.max()
    return float(-(m + np.log(np.exp(z - m).sum())))


@dataclass(frozen=True)
class PhotoCheckConfig:
    min_skin_fraction: float
    max_energy: float
    energy_on: str = "raw"            # 'raw' logits (v1) or 'calibrated': (logits + logit_adjust) / temperature (v3)
    model_version: str | None = None  # the model the energy threshold was set for

    @classmethod
    def load(cls, path: str | Path) -> "PhotoCheckConfig":
        c = json.loads(Path(path).read_text())
        energy_on = c.get("energy_on", "raw")
        if energy_on.startswith("v3 logits / temperature"):      # how notebook 19 wrote it
            energy_on = "calibrated"
        if energy_on not in ("raw", "calibrated"):
            raise ValueError(f"Unknown energy_on in {path}: {energy_on!r}")
        return cls(min_skin_fraction=float(c["min_skin_fraction"]), max_energy=float(c["max_energy"]),
                   energy_on=energy_on, model_version=c.get("model_version"))

    def status(self, skin: float, energy: float) -> str:
        if skin < self.min_skin_fraction:
            return "no_skin"
        if energy > self.max_energy:
            return "nothing_detected"
        return "ok"


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
    head_file: str | None = None        # v3 only: the classifier arrays; None means the ONNX model gives logits (v1)
    preprocessing: dict | None = None   # v3 only

    @property
    def kind(self) -> str:
        return "encoder_head" if self.head_file else "effb0"

    @classmethod
    def load(cls, path: str | Path) -> "ModelConfig":
        c = json.loads(Path(path).read_text())
        if "head_file" in c:                          # v3 format, written by ml/19_final_v3.ipynb
            pre = c["preprocessing"]
            if pre.get("resize_library", "PIL") != "PIL":
                raise ValueError("The v3 config expects a resize library other than Pillow.")
            return cls(model_version=c["model_version"], classes=list(c["classes"]), img_size=int(pre["size"][0]),
                       temperature=float(c["temperature"]), logit_adjust=[float(v) for v in c["logit_adjust"]],
                       high_from=float(c["bands"]["high_from"]), refer_below=float(c["bands"]["refer_below"]),
                       cap_at_moderate=["scabies"] if c.get("scabies_never_high") else [],
                       onnx_sha256=c.get("onnx_sha256"), model_file=c["onnx_file"], head_file=c["head_file"],
                       preprocessing=pre)
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
    status: str = "ok"          # 'ok' | 'no_skin' | 'nothing_detected' (photo check)
    skin_fraction: float | None = None
    energy: float | None = None
    timing_ms: dict | None = None   # time spent per step, for measuring speed (not stored with the screening)

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

    def __init__(self, model_path: str | Path, config_path: str | Path, verify_checksum: bool = True,
                 photo_check_path: str | Path | None = None, threads: int | None = None):
        import onnxruntime as ort

        self.config = ModelConfig.load(config_path)
        self.photo_check = PhotoCheckConfig.load(photo_check_path) if photo_check_path else None
        if self.photo_check and self.photo_check.model_version and self.photo_check.model_version != self.config.model_version:
            raise RuntimeError(f"{Path(photo_check_path).name} was set for {self.photo_check.model_version}, but the model "
                               f"is {self.config.model_version}. Use the photo check file that belongs to this model.")
        model_path = Path(model_path)
        if not model_path.exists():
            raise RuntimeError(f"Model file {model_path.name} is missing from {model_path.parent}. "
                               "Download it from Google Drive (see backend/models/README.md).")
        if verify_checksum and self.config.onnx_sha256:
            actual = sha256_of(model_path)
            if actual != self.config.onnx_sha256:
                raise RuntimeError(f"Model file does not match its config (sha256 {actual[:12]}..., "
                                   f"expected {self.config.onnx_sha256[:12]}...). Re-download both from Drive.")
        self.head = None
        if self.config.head_file:
            self.head = LinearHead(Path(config_path).parent / self.config.head_file)
            if len(self.head.intercept) != len(self.config.classes):
                raise RuntimeError("The classifier file does not match the classes in the config.")
        options = ort.SessionOptions()
        options.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
        if threads:
            options.intra_op_num_threads = int(threads)
        self.session = ort.InferenceSession(str(model_path), options, providers=["CPUExecutionProvider"])
        self.input_name = self.session.get_inputs()[0].name

    @classmethod
    def from_dir(cls, models_dir: str | Path, config_name: str = "lumis_model_config.json",
                 photo_check_name: str | None = None, threads: int | None = None) -> "LumisPredictor":
        """Load the config in models_dir and the ONNX file it names. photo_check_name None means
        photo_check.json if it exists (v1 behavior); a name that is given must exist."""
        models_dir = Path(models_dir)
        config_path = models_dir / config_name
        if photo_check_name is None:
            photo_check = models_dir / "photo_check.json"
            photo_check = photo_check if photo_check.exists() else None
        else:
            photo_check = models_dir / photo_check_name
            if not photo_check.exists():
                raise RuntimeError(f"Photo check file {photo_check_name} is missing from {models_dir}.")
        return cls(models_dir / ModelConfig.load(config_path).model_file, config_path,
                   photo_check_path=photo_check, threads=threads)

    def logits(self, batch: np.ndarray) -> np.ndarray:
        """Raw logits for a preprocessed batch (v1: the CNN; v3: encoder then classifier)."""
        out = self.session.run(None, {self.input_name: batch.astype(np.float32)})[0]
        return self.head.logits(out) if self.head is not None else out

    def energy(self, logits: np.ndarray) -> float:
        if self.photo_check and self.photo_check.energy_on == "calibrated":
            return energy_score((np.asarray(logits, np.float64) + np.asarray(self.config.logit_adjust))
                                / self.config.temperature)
        return energy_score(logits)

    def predict(self, data: bytes) -> Prediction:
        t0 = time.perf_counter()
        if self.head is not None:
            img = open_image(data)
            rgb = np.asarray(img)
            x = to_encoder_input(img, self.config.preprocessing)
        else:
            rgb = decode_image(data)
            x = to_model_input(rgb, self.config.img_size)
        skin = skin_fraction(rgb)
        t1 = time.perf_counter()
        raw = self.session.run(None, {self.input_name: x})[0]
        t2 = time.perf_counter()
        logits = (self.head.logits(raw) if self.head is not None else raw)[0]
        energy = self.energy(logits)
        status = self.photo_check.status(skin, energy) if self.photo_check else "ok"
        result = postprocess(logits, self.config)
        t3 = time.perf_counter()
        timing = {"preprocess": round((t1 - t0) * 1000, 1), "model": round((t2 - t1) * 1000, 1),
                  "postprocess": round((t3 - t2) * 1000, 1), "total": round((t3 - t0) * 1000, 1)}
        log.info("prediction %s in %.0f ms (model %.0f ms)", self.config.model_version, timing["total"], timing["model"])
        return replace(result, status=status, skin_fraction=round(skin, 4), energy=round(energy, 4), timing_ms=timing)
