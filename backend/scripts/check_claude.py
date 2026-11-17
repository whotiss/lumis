"""Send one Claude check exactly as the backend does and show the result, or Anthropic's full error message.

Run from the backend folder. The key is read from ANTHROPIC_API_KEY (or backend/.env) and is never printed.
To test the key stored for the server, in PowerShell:
    $env:ANTHROPIC_API_KEY = gcloud secrets versions access latest --secret lumis-anthropic-key
    python scripts/check_claude.py
    Remove-Item Env:ANTHROPIC_API_KEY
Costs one small Claude request (a fraction of a US cent). The picture sent is generated, not a photo.
"""
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import numpy as np                                                  # noqa: E402

from app.config import get_settings                                 # noqa: E402
from app.ml.claude_check import ClaudeCheckConfig, build_request, parse_response, prepare_image   # noqa: E402


def main() -> int:
    import anthropic

    s = get_settings()
    key = (s.anthropic_api_key or "").strip()
    if not key:
        print("No key found: set ANTHROPIC_API_KEY first (see the top of this script).")
        return 1
    cfg = ClaudeCheckConfig.load(s.model_dir / "claude_check.json")
    print(f"Key: {len(key)} characters, starts with {key[:7]}... | model {cfg.model} | "
          f"anthropic library {anthropic.__version__}")

    rgb = np.clip(np.random.default_rng(0).normal([205, 150, 125], 8, (480, 640, 3)), 0, 255).astype(np.uint8)
    request = build_request(prepare_image(rgb), ["eczema", "tinea"], {"eczema": "Eczema", "tinea": "Tinea"}, cfg.model)
    client = anthropic.Anthropic(api_key=key, timeout=30, max_retries=0)
    t = time.perf_counter()
    try:
        response = client.messages.create(**request)
    except anthropic.APIStatusError as exc:
        print(f"\nFAILED after {time.perf_counter() - t:.1f} s: HTTP {exc.status_code} {type(exc).__name__}")
        body = exc.body if isinstance(exc.body, dict) else {}
        print("Anthropic says:", (body.get("error") or {}).get("message") or exc.message)
        return 1
    except anthropic.APIConnectionError as exc:
        print(f"\nFAILED: could not reach Anthropic ({type(exc).__name__}): {exc}")
        return 1
    verdict = parse_response(response, ["eczema", "tinea"], cfg.model)
    print(f"\nOK in {time.perf_counter() - t:.1f} s: {verdict.to_dict()}")
    return 0 if verdict.ok else 1


if __name__ == "__main__":
    sys.exit(main())
