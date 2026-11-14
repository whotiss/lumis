"""Measure how long the model takes per photo on this computer (for the speed table in the report).

Run from the backend folder, with the model files in models/:
    python scripts/time_model.py                       # a generated test photo, 10 runs
    python scripts/time_model.py path/to/photo.jpg     # your own photos (one or more files or a folder)
    python scripts/time_model.py --runs 20 --threads 4 --out timing.json

It uses the same settings as the API (MODEL_CONFIG_FILE, PHOTO_CHECK_FILE, ONNX_THREADS from backend/.env).
Photos are only read, never stored or sent anywhere.
"""
import argparse
import io
import json
import os
import platform
import statistics
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import numpy as np                                    # noqa: E402
import onnxruntime as ort                             # noqa: E402
from PIL import Image                                 # noqa: E402

from app.config import get_settings                   # noqa: E402
from app.ml.predictor import LumisPredictor           # noqa: E402

PHOTO_TYPES = {".jpg", ".jpeg", ".png", ".webp"}


def test_photo() -> bytes:
    rng = np.random.default_rng(0)
    yy, xx = np.mgrid[0:3000, 0:4000]
    base = np.stack([170 + xx / 80, 110 + yy / 60, 90 + (xx + yy) % 30], -1) + rng.normal(0, 8, (3000, 4000, 3))
    b = io.BytesIO()
    Image.fromarray(np.clip(base, 0, 255).astype(np.uint8)).save(b, "JPEG", quality=90)   # like a 12 MP phone photo
    return b.getvalue()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("photos", nargs="*", help="photo files or folders (default: a generated 12 MP test photo)")
    ap.add_argument("--runs", type=int, default=10, help="timed runs per photo (after 2 warm-up runs)")
    ap.add_argument("--threads", type=int, default=None, help="ONNX Runtime threads (default: settings or all cores)")
    ap.add_argument("--out", help="also save the results to this JSON file")
    args = ap.parse_args()

    files = []
    for p in map(Path, args.photos):
        files += sorted(f for f in p.iterdir() if f.suffix.lower() in PHOTO_TYPES) if p.is_dir() else [p]
    photos = [(f.name, f.read_bytes()) for f in files] or [("generated 4000x3000 JPEG", test_photo())]

    s = get_settings()
    threads = args.threads or s.onnx_threads
    t0 = time.perf_counter()
    predictor = LumisPredictor.from_dir(s.model_dir, s.model_config_file, s.photo_check_file, threads=threads)
    load_s = time.perf_counter() - t0
    print(f"{predictor.config.model_version} loaded in {load_s:.1f} s (includes the file checksum) | "
          f"{os.cpu_count()} logical cores | threads {threads or 'all'} | ONNX Runtime {ort.__version__} | "
          f"{platform.processor() or platform.machine()}")

    rows = []
    for name, data in photos:
        for _ in range(2):
            predictor.predict(data)                    # warm-up
        runs = [predictor.predict(data).timing_ms for _ in range(args.runs)]
        row = {"photo": name, "runs": args.runs}
        for step in ("preprocess", "model", "postprocess", "total"):
            values = [r[step] for r in runs]
            row[step] = {"median_ms": statistics.median(values), "min_ms": min(values), "max_ms": max(values)}
        rows.append(row)
        print(f"{name}: total {row['total']['median_ms'] / 1000:.2f} s per photo (median of {args.runs}; "
              f"model {row['model']['median_ms'] / 1000:.2f} s, preprocessing {row['preprocess']['median_ms']:.0f} ms)")

    if args.out:
        result = {"model_version": predictor.config.model_version, "load_seconds": round(load_s, 2),
                  "logical_cores": os.cpu_count(), "threads": threads, "onnxruntime": ort.__version__,
                  "platform": platform.platform(), "processor": platform.processor(), "photos": rows,
                  "measured_at": time.strftime("%Y-%m-%d %H:%M")}
        Path(args.out).write_text(json.dumps(result, indent=1))
        print("Saved", args.out)


if __name__ == "__main__":
    main()
