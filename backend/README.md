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
The model files must be in `models/` first (see `models/README.md`).
Local development uses a SQLite file (`lumis_dev.db`) and stores photos in `uploads/`; both are git-ignored.

## Tests

```
python -m pytest -q
```

## Endpoints (stage 1)

| Method and path | What it does | CP1 |
|---|---|---|
| POST /auth/register | Create account (Argon2id salted hash), returns token | FR11 |
| POST /auth/login | Log in (form fields username, password), returns token | FR11 |
| GET /me, PATCH /me/consent, DELETE /me | Account, time-stamped consent, delete everything | NFR4 |
| POST /screenings | Upload photo plus optional symptoms, returns band, wording, disclaimer | FR1-4, FR9 |
| GET /screenings, GET /screenings/{id} | History, newest first | FR7 |
| GET /screenings/{id}/image | Stored photo (only if the user consented to storage) | FR7 |
| DELETE /screenings/{id} | Delete a screening and its photo | FR10 |
| GET /conditions | Reference information for the five conditions | FR8 |
| GET /model, GET /health | Model version and test results; health check | NFR7 |

All result wording lives in `app/wording.py`, so screening-aid positioning (NFR8) is enforced in one place.
