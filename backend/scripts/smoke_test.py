"""Check a running Lumis backend end to end (after a deploy, or locally).

    python scripts/smoke_test.py https://YOUR-SERVICE-URL --photo path/to/a_skin_photo.jpg
    python scripts/smoke_test.py http://127.0.0.1:8000 --photo path/to/a_skin_photo.jpg

What it does: health check, model info, registers a temporary account, sends the photo for a screening,
reads the history, downloads the stored photo and compares it, deletes the screening, then deletes the
temporary account. Nothing is left behind on the server. It prints how long each step took.

The photo is sent to your own server (and, if the Claude check is on, to Anthropic for the skin check),
exactly like a photo from the app. Use a photo you are allowed to use; keep personal photos out of git.
Without --photo a generated picture is sent: that only shows that a non-skin picture is rejected.
"""
import argparse
import io
import secrets
import sys
import time

import httpx


def generated_picture() -> bytes:
    from PIL import Image
    b = io.BytesIO()
    Image.new("RGB", (800, 600), (30, 80, 200)).save(b, "JPEG")
    return b.getvalue()


def step(name, started, extra=""):
    print(f"  ok  {name:<34} {time.perf_counter() - started:6.2f} s  {extra}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("url", help="base URL of the backend, for example https://lumis-api-xxxx.a.run.app")
    ap.add_argument("--photo", help="a skin photo (JPEG, PNG or WebP)")
    ap.add_argument("--timeout", type=float, default=180, help="seconds to wait per request (a cold start is slow)")
    args = ap.parse_args()

    photo = open(args.photo, "rb").read() if args.photo else generated_picture()
    email = f"smoke-{secrets.token_hex(6)}@example.com"
    password = secrets.token_urlsafe(16)
    failures = []
    headers = None

    with httpx.Client(base_url=args.url.rstrip("/"), timeout=args.timeout) as c:
        try:
            t = time.perf_counter()
            r = c.get("/health")
            r.raise_for_status()
            step("health", t, f"model {r.json()['model_version']} (the first call includes any cold start)")

            t = time.perf_counter()
            info = c.get("/model").json()
            step("model info", t, f"bands {info['bands']}")

            t = time.perf_counter()
            r = c.post("/auth/register", json={"email": email, "password": password, "consent_storage": True})
            r.raise_for_status()
            headers = {"Authorization": f"Bearer {r.json()['access_token']}"}
            step("register temporary account", t)

            t = time.perf_counter()
            r = c.post("/auth/login", data={"username": email, "password": password})
            r.raise_for_status()
            step("log in", t)

            t = time.perf_counter()
            r = c.post("/screenings", headers=headers, files={"image": ("photo.jpg", photo, "image/jpeg")})
            timing = r.headers.get("server-timing", "no timing header")
            if r.status_code == 201:
                s = r.json()
                step("screening", t, f"{s['band_label']}: {s['headline']}")
                print(f"      server timing: {timing}")

                t = time.perf_counter()
                history = c.get("/screenings", headers=headers).json()
                assert [h["id"] for h in history] == [s["id"]], "history does not show the screening"
                step("history", t)

                t = time.perf_counter()
                img = c.get(f"/screenings/{s['id']}/image", headers=headers)
                assert img.status_code == 200 and img.content == photo, "stored photo differs from the upload"
                step("stored photo comes back identical", t)

                t = time.perf_counter()
                assert c.delete(f"/screenings/{s['id']}", headers=headers).status_code == 204
                assert c.get(f"/screenings/{s['id']}/image", headers=headers).status_code == 404
                step("delete screening and photo", t)
            elif r.status_code == 422 and isinstance(r.json().get("detail"), dict):
                d = r.json()["detail"]
                step("screening (photo check stopped it)", t, f"{d['code']}: {d['headline']}")
                print(f"      server timing: {timing}")
                if args.photo:
                    failures.append("the photo was rejected by the photo check, so storage was not tested: "
                                    "try a clearer close-up skin photo")
                elif d["code"] != "no_skin":
                    failures.append(f"the generated blue picture should give no_skin, got {d['code']}")
            else:
                failures.append(f"screening returned {r.status_code}: {r.text[:300]}")
        except (httpx.HTTPError, AssertionError, KeyError) as exc:
            failures.append(f"{type(exc).__name__}: {exc}")
        finally:
            if headers:
                t = time.perf_counter()
                r = c.delete("/me", headers=headers)
                if r.status_code == 204 and c.get("/me", headers=headers).status_code == 401:
                    step("delete temporary account", t)
                else:
                    failures.append(f"could not delete the temporary account {email} (status {r.status_code})")

    if failures:
        print("\nFAILED:")
        for f in failures:
            print(" -", f)
        return 1
    if args.photo:
        print("\nAll steps passed: database, photo storage, model and photo check work end to end.")
    else:
        print("\nPassed without a skin photo: accounts, database and the photo check work. "
              "Run again with --photo to test a full screening and photo storage.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
