# Lumis backend

FastAPI service: accounts, photo screening with the exported model, history, condition reference.

## Run locally (Windows, macOS or Linux, Python 3.10+)

```
cd backend
python -m venv .venv
.venv\Scripts\activate          (macOS/Linux: source .venv/bin/activate)
pip install -r requirements.txt
uvicorn app.main:app --reload
```

Open http://127.0.0.1:8000/docs to try every endpoint in the browser.
The model files must be in `models/` first (see `models/README.md`): for model v3, download
`lumis_medsiglip_v3.onnx` (1.71 GB) from Drive `Lumis/exports/model_v3/`. The first start takes a few seconds
longer because the file's checksum is verified.

To measure the model's speed on this computer: `python scripts/time_model.py`
Local development uses a SQLite file (`lumis_dev.db`) and stores photos in `uploads/`; both are git-ignored.

## Tests

```
python -m pytest -q
```

The tests for the server-only parts (production settings, photo storage in a bucket) use stand-ins and need no
network. Two more run the whole API on a real PostgreSQL database when `TEST_DATABASE_URL` is set to an empty
test database.

## Deploying (Google Cloud Run)

Step-by-step guide: [`deploy/README.md`](deploy/README.md). In short: the backend and model v3 run on Cloud Run
in Singapore, the database is PostgreSQL on Neon, stored photos go to a private Cloud Storage bucket, and
secrets live in Secret Manager. Useful scripts:

| Script | What it does |
|---|---|
| `python scripts/check_model.py` | Are the model files present and do they belong together? (also run during the image build) |
| `python scripts/smoke_test.py URL --photo photo.jpg` | End-to-end check of a running backend; cleans up after itself |
| `python scripts/time_model.py` | Time per photo on this computer or server |
| `python deploy/set_secret.py NAME` | Save a secret in Secret Manager with hidden typing |

## Endpoints (stage 1)

| Method and path | What it does | CP1 |
|---|---|---|
| POST /auth/register | Create account (Argon2id salted hash), returns token | FR11 |
| POST /auth/login | Log in (form fields username, password), returns token | FR11 |
| GET /me, PATCH /me/consent, DELETE /me | Account, time-stamped consent, delete everything | NFR4 |
| POST /screenings | Upload photo plus optional symptoms, returns band, wording, disclaimer and the explanation (what it is, common signs, Claude's description of the photo, what to do) | FR1-5, FR9 |
| GET /screenings, GET /screenings/{id} | History, newest first | FR7 |
| GET /screenings/{id}/image | Stored photo (only if the user consented to storage) | FR7 |
| DELETE /screenings/{id} | Delete a screening and its photo | FR10 |
| GET /conditions | Reference information for the five conditions | FR8 |
| GET /model, GET /health | Model version and test results; health check | NFR7 |
| GET /consent?lang=en or ms | Consent text to show before registering (versioned; English and Malay) | NFR4 |
| POST /me/consent/accept | Agree to a new consent version; screenings are refused until then | NFR4 |
| GET /clinics | Every dermatology place in the Klang Valley directory, A to Z (filter with `?type=`) | FR6 |
| POST /clinics/nearby | The nearest places to a location, with straight-line distance; the location is not stored or logged | FR6 |

The clinic directory is `app/data/clinics.json`; how it was made and how to update it is in `docs/clinic_directory.md`.

All result wording lives in `app/wording.py`, so screening-aid positioning (NFR8) is enforced in one place.
