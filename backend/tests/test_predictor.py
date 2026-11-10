"""Tests for app/ml/predictor.py. Run from the backend folder: python -m pytest -q"""
import io
from pathlib import Path

import numpy as np
import pytest
from PIL import Image, ImageOps

from app.ml.predictor import (ModelConfig, UnsupportedImageError, LumisPredictor, decode_image,
                              postprocess, preprocess, resize_like_tf)

MODELS = Path(__file__).resolve().parents[1] / "models"


def make_image(w=320, h=240, seed=0):
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:h, 0:w]
    base = np.stack([xx * 255 / w, yy * 255 / h, (xx + yy) % 256], -1) + rng.normal(0, 20, (h, w, 3))
    return Image.fromarray(np.clip(base, 0, 255).astype(np.uint8))


def encode(im, fmt="JPEG", **kw):
    b = io.BytesIO()
    im.save(b, fmt, **kw)
    return b.getvalue()


def cfg(**over):
    base = dict(model_version="test", classes=["acne", "eczema", "psoriasis", "scabies", "tinea"], img_size=224,
                temperature=1.0, logit_adjust=[0.0] * 5, high_from=0.74, refer_below=0.52,
                cap_at_moderate=["scabies"])
    base.update(over)
    return ModelConfig(**base)


# ---------------------------------------------------------------- preprocessing

@pytest.mark.parametrize("fmt", ["JPEG", "PNG", "WEBP"])
def test_formats_give_model_input(fmt):
    x = preprocess(encode(make_image(), fmt))
    assert x.shape == (1, 224, 224, 3) and x.dtype == np.float32
    assert 0 <= x.min() and x.max() <= 255


def test_png_with_alpha_and_grayscale():
    assert preprocess(encode(make_image().convert("RGBA"), "PNG")).shape == (1, 224, 224, 3)
    assert preprocess(encode(make_image().convert("L"), "JPEG")).shape == (1, 224, 224, 3)


@pytest.mark.parametrize("orientation", range(1, 9))
def test_exif_orientation_matches_pillow(orientation):
    im = make_image(64, 48)
    exif = Image.Exif()
    exif[0x0112] = orientation
    data = encode(im, "PNG", exif=exif)
    expected = np.asarray(ImageOps.exif_transpose(Image.open(io.BytesIO(data))).convert("RGB"))
    assert np.array_equal(decode_image(data), expected)


def test_rejects_non_images_and_other_formats():
    with pytest.raises(UnsupportedImageError):
        preprocess(b"not an image at all")
    with pytest.raises(UnsupportedImageError):
        preprocess(encode(make_image(), "GIF"))


def test_resize_identity_at_same_size():
    img = np.asarray(make_image(224, 224))
    assert np.array_equal(resize_like_tf(img, 224).astype(np.uint8), img)


def test_matches_tensorflow_pipeline_if_installed():
    tf = pytest.importorskip("tensorflow")
    for w, h, fmt in [(640, 480, "JPEG"), (1000, 750, "JPEG"), (300, 200, "PNG"), (500, 333, "WEBP")]:
        data = encode(make_image(w, h, seed=w), fmt)
        img = tf.io.decode_image(data, channels=3, expand_animations=False)
        ref = tf.cast(tf.cast(tf.image.resize(img, (224, 224)), tf.uint8), tf.float32).numpy()
        ours = preprocess(data)[0]
        assert np.abs(ours - ref).max() <= 1, fmt                 # float rounding only
        assert (ours != ref).mean() < 0.001, fmt


# ---------------------------------------------------------------- output -> result

def test_bands():
    c = cfg()
    assert postprocess(np.array([5.0, 0, 0, 0, 0]), c).band == "high"
    assert postprocess(np.array([1.8, 0, 0, 0, 0]), c).band == "moderate"   # 0.60
    assert postprocess(np.array([0.3, 0, 0, 0, 0]), c).band == "refer"


def test_scabies_never_high():
    p = postprocess(np.array([0, 0, 0, 6.0, 0]), cfg())
    assert p.condition == "scabies" and p.band == "moderate" and p.capped
    assert not postprocess(np.array([0, 0, 0, 0, 6.0]), cfg()).capped


def test_temperature_and_adjustment_are_applied():
    logits = np.array([1.0, 0.8, 0, 0, 0])
    assert postprocess(logits, cfg()).condition == "acne"
    assert postprocess(logits, cfg(logit_adjust=[0, 0.5, 0, 0, 0])).condition == "eczema"
    sharp, soft = postprocess(logits, cfg(temperature=0.5)), postprocess(logits, cfg(temperature=2.0))
    assert sharp.confidence > soft.confidence
    assert abs(sum(sharp.probabilities.values()) - 1) < 1e-3


# ---------------------------------------------------------------- the real model (skipped until downloaded)

@pytest.mark.skipif(not (MODELS / "lumis_model_config.json").exists(), reason="model not downloaded yet")
def test_real_model_runs():
    predictor = LumisPredictor.from_dir(MODELS)
    result = predictor.predict(encode(make_image(), "JPEG"))
    assert result.band in {"high", "moderate", "refer"}
    assert result.condition in predictor.config.classes
