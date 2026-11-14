"""Tests for the v3 path of app/ml/predictor.py (MedSigLIP encoder + classifier), using a tiny stand-in encoder,
plus a check of the real v3 files when they have been downloaded. Run from the backend folder: python -m pytest -q"""
import hashlib
import io
import json
from pathlib import Path

import numpy as np
import pytest
from PIL import Image, ImageOps

from app.ml.predictor import (LinearHead, LumisPredictor, ModelConfig, PhotoCheckConfig, UnsupportedImageError,
                              energy_score, open_image, skin_fraction, softmax, to_encoder_input)

onnx = pytest.importorskip("onnx")
from onnx import TensorProto, helper, numpy_helper  # noqa: E402

MODELS = Path(__file__).resolve().parents[1] / "models"
CLASSES = ["acne", "eczema", "psoriasis", "scabies", "tinea"]
ADJ = [-0.22778, 0.41253, 0.27813, -0.64123, 0.17835]
PRE = {"size": [448, 448], "resample": 3, "rescale_factor": 0.00392156862, "image_mean": [0.5, 0.5, 0.5],
       "image_std": [0.5, 0.5, 0.5], "exif_transpose": True, "color": "RGB", "resize_library": "PIL"}
D, P = 8, 4                     # stand-in embedding size and PCA size (the real ones are 1152 and 256)
W = np.random.default_rng(1).normal(size=(3, D)).astype(np.float32)


def make_photo(w=500, h=380, seed=0, fmt="JPEG", exif_orientation=None, mode="RGB"):
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:h, 0:w]
    base = np.stack([150 + xx * 80 / w, 90 + yy * 60 / h, 80 + (xx + yy) % 40], -1) + rng.normal(0, 10, (h, w, 3))
    im = Image.fromarray(np.clip(base, 0, 255).astype(np.uint8)).convert(mode)
    kw = {}
    if exif_orientation:
        exif = Image.Exif()
        exif[0x0112] = exif_orientation
        kw["exif"] = exif
    b = io.BytesIO()
    im.save(b, fmt, **kw)
    return b.getvalue()


def notebook19_input(data):
    """Independent copy of notebook 19: open_rgb then preprocess_np."""
    img = ImageOps.exif_transpose(Image.open(io.BytesIO(data))).convert("RGB")
    a = np.asarray(img.resize((448, 448), resample=3), dtype=np.float32) * 0.00392156862
    a = (a - np.array([0.5] * 3, np.float32)) / np.array([0.5] * 3, np.float32)
    return a.transpose(2, 0, 1)[None]


def tiny_encoder(path):
    """(N, 3, 448, 448) -> mean of each channel -> times W -> (N, D) 'embedding'."""
    nodes = [helper.make_node("ReduceMean", ["pixel_values"], ["m"], axes=[2, 3], keepdims=0),
             helper.make_node("MatMul", ["m", "W"], ["embedding"])]
    graph = helper.make_graph(nodes, "tiny", [helper.make_tensor_value_info("pixel_values", TensorProto.FLOAT, ["batch", 3, 448, 448])],
                              [helper.make_tensor_value_info("embedding", TensorProto.FLOAT, ["batch", D])],
                              [numpy_helper.from_array(W, "W")])
    model = helper.make_model(graph, opset_imports=[helper.make_opsetid("", 17)])
    model.ir_version = 8
    onnx.save(model, path)


@pytest.fixture
def v3dir(tmp_path):
    tiny_encoder(tmp_path / "enc.onnx")
    rng = np.random.default_rng(2)
    np.savez(tmp_path / "head.npz", scaler_mean=rng.normal(size=D).astype(np.float32),
             scaler_scale=rng.uniform(0.5, 2, D).astype(np.float32), pca_mean=np.zeros(D, np.float32),
             pca_components=rng.normal(size=(P, D)).astype(np.float32), coef=rng.normal(size=(5, P)).astype(np.float32),
             intercept=rng.normal(size=5).astype(np.float32))
    cfg = {"version": "v3", "model_version": "test-v3", "onnx_file": "enc.onnx",
           "onnx_sha256": hashlib.sha256((tmp_path / "enc.onnx").read_bytes()).hexdigest(), "head_file": "head.npz",
           "classes": CLASSES, "logit_adjust": ADJ, "temperature": 1.25,
           "bands": {"high_from": 0.64, "moderate_from": 0.2, "refer_below": 0.2}, "scabies_never_high": True,
           "preprocessing": PRE}
    (tmp_path / "cfg.json").write_text(json.dumps(cfg))
    (tmp_path / "pc.json").write_text(json.dumps({"min_skin_fraction": 0.0219, "max_energy": 100.0,
                                                  "energy_on": "calibrated", "model_version": "test-v3"}))
    return tmp_path


def expected_logits(data, d):
    x = notebook19_input(data)
    emb = x.mean(axis=(2, 3)) @ W
    h = np.load(d / "head.npz")
    z = ((emb - h["scaler_mean"]) / h["scaler_scale"] - h["pca_mean"]) @ h["pca_components"].T
    return (z @ h["coef"].T + h["intercept"])[0]


# ---------------------------------------------------------------- config and preprocessing

def test_v3_config_is_read(v3dir):
    c = ModelConfig.load(v3dir / "cfg.json")
    assert c.kind == "encoder_head" and c.model_file == "enc.onnx" and c.head_file == "head.npz"
    assert c.img_size == 448 and c.cap_at_moderate == ["scabies"] and c.refer_below == 0.2
    assert ModelConfig.load(MODELS / "lumis_model_config.json").kind == "effb0"


@pytest.mark.parametrize("orientation", [None, 3, 6, 8])
@pytest.mark.parametrize("fmt,mode", [("JPEG", "RGB"), ("PNG", "RGBA"), ("PNG", "L"), ("WEBP", "RGB")])
def test_preprocessing_matches_notebook19(fmt, mode, orientation):
    data = make_photo(fmt=fmt, mode=mode, exif_orientation=orientation)
    x = to_encoder_input(open_image(data), PRE)
    assert x.shape == (1, 3, 448, 448) and x.dtype == np.float32
    assert np.array_equal(x, notebook19_input(data))
    assert -1.0 - 1e-6 <= x.min() and x.max() <= 1.0 + 1e-6


def test_exif_rotation_is_applied():
    data = make_photo(500, 300, exif_orientation=6)              # stored sideways: shown upright as 300 x 500
    assert open_image(data).size == (300, 500)


def test_v3_rejects_bad_files():
    with pytest.raises(UnsupportedImageError):
        open_image(b"not an image")
    b = io.BytesIO()
    Image.new("RGB", (10, 10)).save(b, "GIF")
    with pytest.raises(UnsupportedImageError):
        open_image(b.getvalue())


def test_photo_check_reads_notebook19_wording():
    pc = PhotoCheckConfig.load(MODELS / "photo_check_v3.json")
    assert pc.energy_on == "calibrated" and pc.model_version == "lumis-medsiglip-v3"
    assert PhotoCheckConfig.load(MODELS / "photo_check.json").energy_on == "raw"


# ---------------------------------------------------------------- predictions

def test_v3_prediction_matches_independent_computation(v3dir):
    p = LumisPredictor(v3dir / "enc.onnx", v3dir / "cfg.json", photo_check_path=v3dir / "pc.json")
    data = make_photo(seed=3)
    pred = p.predict(data)
    z = expected_logits(data, v3dir)
    probs = softmax((z + np.array(ADJ)) / 1.25)
    assert pred.condition == CLASSES[int(probs.argmax())] and pred.model_version == "test-v3"
    assert pred.confidence == pytest.approx(float(probs.max()), abs=1e-4)
    assert [pred.probabilities[c] for c in CLASSES] == pytest.approx(probs.tolist(), abs=1e-4)
    assert pred.energy == pytest.approx(energy_score((z + np.array(ADJ)) / 1.25), abs=0.02)   # calibrated energy
    assert abs(pred.energy - energy_score(z)) > 0.5                                            # not the raw one
    assert set(pred.timing_ms) == {"preprocess", "model", "postprocess", "total"}


def test_v3_energy_threshold_uses_calibrated_logits(v3dir):
    data = make_photo(seed=4)
    p = LumisPredictor(v3dir / "enc.onnx", v3dir / "cfg.json")
    z = p.logits(to_encoder_input(open_image(data), PRE))[0]
    calibrated, raw = energy_score((z + np.array(ADJ)) / 1.25), energy_score(z)
    assert abs(calibrated - raw) > 0.5
    statuses = {}
    for mode in ("calibrated", "raw"):                            # threshold halfway between the two energies
        (v3dir / f"pc_{mode}.json").write_text(json.dumps({"min_skin_fraction": 0.0, "max_energy": (calibrated + raw) / 2,
                                                           "energy_on": mode, "model_version": "test-v3"}))
        statuses[mode] = LumisPredictor(v3dir / "enc.onnx", v3dir / "cfg.json",
                                        photo_check_path=v3dir / f"pc_{mode}.json").predict(data).status
    assert statuses["calibrated"] == ("nothing_detected" if calibrated > raw else "ok")
    assert statuses["calibrated"] != statuses["raw"]


def test_v3_no_skin(v3dir):
    p = LumisPredictor(v3dir / "enc.onnx", v3dir / "cfg.json", photo_check_path=v3dir / "pc.json")
    b = io.BytesIO()
    Image.new("RGB", (400, 300), (30, 80, 200)).save(b, "JPEG")
    assert p.predict(b.getvalue()).status == "no_skin"


def test_v3_scabies_never_high(v3dir):
    p = LumisPredictor(v3dir / "enc.onnx", v3dir / "cfg.json")
    from app.ml.predictor import postprocess
    pred = postprocess(np.array([0, 0, 0, 9.0, 0]), p.config)
    assert pred.condition == "scabies" and pred.band == "moderate" and pred.capped


# ---------------------------------------------------------------- safety checks at startup

def test_wrong_or_missing_files_are_refused(v3dir):
    with pytest.raises(RuntimeError, match="missing"):
        LumisPredictor(v3dir / "nothing.onnx", v3dir / "cfg.json")
    with pytest.raises(RuntimeError, match="does not match"):
        cfg = json.loads((v3dir / "cfg.json").read_text())
        cfg["onnx_sha256"] = "0" * 64
        (v3dir / "bad.json").write_text(json.dumps(cfg))
        LumisPredictor(v3dir / "enc.onnx", v3dir / "bad.json")
    pc = json.loads((v3dir / "pc.json").read_text())
    pc["model_version"] = "lumis-effb0-v1"                       # a v1 photo check with a v3 model
    (v3dir / "pc_v1.json").write_text(json.dumps(pc))
    with pytest.raises(RuntimeError, match="photo check file"):
        LumisPredictor(v3dir / "enc.onnx", v3dir / "cfg.json", photo_check_path=v3dir / "pc_v1.json")
    with pytest.raises(RuntimeError, match="missing"):
        LumisPredictor.from_dir(v3dir, "cfg.json", "no_such_photo_check.json")


def test_from_dir_and_threads(v3dir):
    p = LumisPredictor.from_dir(v3dir, "cfg.json", "pc.json", threads=1)
    assert p.photo_check.energy_on == "calibrated" and p.predict(make_photo()).condition in CLASSES


# ---------------------------------------------------------------- the real v3 files

def test_real_v3_head_and_config_agree():
    """The classifier arrays and config committed in backend/models belong together."""
    cfg = ModelConfig.load(MODELS / "lumis_model_config_v3.json")
    head = LinearHead(MODELS / cfg.head_file)
    assert cfg.model_version == "lumis-medsiglip-v3" and cfg.classes == CLASSES and cfg.logit_adjust == ADJ
    assert head.embedding_dim == 1152 and head.pca_components.shape == (256, 1152) and head.coef.shape == (5, 256)


@pytest.mark.skipif(not (MODELS / "lumis_medsiglip_v3.onnx").exists(), reason="v3 encoder not downloaded yet")
def test_real_v3_model_runs():
    p = LumisPredictor.from_dir(MODELS, "lumis_model_config_v3.json", "photo_check_v3.json")
    pred = p.predict(make_photo(800, 600, seed=5))
    assert pred.model_version == "lumis-medsiglip-v3" and abs(sum(pred.probabilities.values()) - 1) < 1e-3
    print(f"\nv3 on this computer: {pred.timing_ms}")
