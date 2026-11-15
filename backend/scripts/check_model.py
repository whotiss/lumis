"""Check that the model files the settings point to are present and belong together.

Run from the backend folder:  python scripts/check_model.py
It is also run while the server image is built, so a wrong or missing model file stops the build
instead of the running service. Add --load to also load the model once (slower).
"""
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.config import get_settings                                         # noqa: E402
from app.ml.predictor import LinearHead, LumisPredictor, ModelConfig, PhotoCheckConfig, sha256_of   # noqa: E402


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--load", action="store_true", help="also load the model with ONNX Runtime")
    args = ap.parse_args()

    s = get_settings()
    cfg = ModelConfig.load(s.model_dir / s.model_config_file)
    problems = []
    model_path = s.model_dir / cfg.model_file
    if not model_path.exists():
        problems.append(f"{cfg.model_file} is missing from {s.model_dir}")
    elif cfg.onnx_sha256 and sha256_of(model_path) != cfg.onnx_sha256:
        problems.append(f"{cfg.model_file} does not match the checksum in {s.model_config_file}")
    if cfg.head_file:
        if not (s.model_dir / cfg.head_file).exists():
            problems.append(f"{cfg.head_file} is missing from {s.model_dir}")
        elif len(LinearHead(s.model_dir / cfg.head_file).intercept) != len(cfg.classes):
            problems.append(f"{cfg.head_file} does not match the classes in {s.model_config_file}")
    photo_check = s.model_dir / s.photo_check_file
    if not photo_check.exists():
        problems.append(f"{s.photo_check_file} is missing from {s.model_dir}")
    else:
        pc = PhotoCheckConfig.load(photo_check)
        if pc.model_version and pc.model_version != cfg.model_version:
            problems.append(f"{s.photo_check_file} was set for {pc.model_version}, not {cfg.model_version}")
    if not (s.model_dir / "claude_check.json").exists():
        problems.append(f"claude_check.json is missing from {s.model_dir}")
    if problems:
        print("Model files are NOT ready:")
        for p in problems:
            print(" -", p)
        return 1
    if args.load:
        LumisPredictor.from_dir(s.model_dir, s.model_config_file, s.photo_check_file, threads=s.onnx_threads)
    size = model_path.stat().st_size / 1e6
    print(f"Model files OK: {cfg.model_version} ({cfg.model_file}, {size:,.0f} MB, checksum matches"
          f"{', loads' if args.load else ''})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
