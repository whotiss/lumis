# Deploying the Lumis backend to Google Cloud Run

This puts the backend and model v3 on the internet so the app can reach it. All commands are for
**PowerShell**, run from the `backend` folder with the virtual environment active.

## What gets set up

| Part | Where | Why |
|---|---|---|
| Backend + model | Cloud Run, region `asia-southeast1` (Singapore), 8 CPUs, 4 GB memory | Closest region to Malaysia that Cloud Run offers. The model needs about 2.2 GB of memory and is faster with more CPUs. |
| Model file (1.7 GB) | Inside the server image, fetched from a private bucket when the image is built | Too big for git. Google recommends keeping models under 10 GB in the image. The build checks the file against its config. |
| Database | Neon (free plan), PostgreSQL, Singapore | Sleeps when idle and wakes by itself, so a demo never finds it paused. |
| Photos of users who agreed to storage | Private Cloud Storage bucket, Singapore | Cloud Run's own disk is temporary. The bucket is not public; only the backend can read it. |
| Secrets (database address, JWT secret, Anthropic key) | Secret Manager | Never in git, never in the image, never typed into a command. |

The service scales to zero when nobody uses it, so it costs nothing while idle. The price of that is a
**cold start**: the first request after a quiet period waits while the model loads (expect up to about a minute).

## Step 0. Accounts and tools (once)

1. **Google Cloud project.** At <https://console.cloud.google.com> create a project and turn on billing for it
   (Google asks for a card). Write down the **project ID** (not the name).
2. **Budget alert (do not skip).** In the console: Billing, then Budgets & alerts, then Create budget. Amount: US$5,
   with email alerts. This only warns you; it does not stop spending.
3. **Google Cloud CLI.** Install it from <https://cloud.google.com/sdk/docs/install>, open a **new** terminal and run
   `gcloud init`. Sign in and choose your project.
4. **Database.** A free Neon project in region **AWS Asia Pacific (Singapore)**. Link it to the repo with the Neon CLI,
   which writes the connection strings to `lumis/.env.local` (git-ignored; never open it on screen or paste it
   anywhere). From the `lumis` folder (needs Node.js):
   ```powershell
   npm install -g neon@latest
   neon login
   neon init -y --no-agent-setup --no-config --org-id <your org id> --project-id <your project id>
   ```
   The backend does not read that file (local development keeps using SQLite); step 6 copies the address from it
   into Secret Manager.
5. **Model file.** `backend/models/lumis_medsiglip_v3.onnx` must be on this computer (it already is if the tests pass).

## Step 1. Names used by every command

Run this block first **in every new terminal**. Change only the first line.

```powershell
$PROJECT = "your-project-id"
$REGION  = "asia-southeast1"
$MODELS  = "${PROJECT}-models"
$UPLOADS = "${PROJECT}-uploads"
$SA      = "lumis-api@${PROJECT}.iam.gserviceaccount.com"
$IMAGE   = "${REGION}-docker.pkg.dev/${PROJECT}/lumis/lumis-api:latest"
$CONTACT = "your-contact-email@example.com"     # shown in the consent text for data requests
gcloud config set project $PROJECT
```

## Step 2. Turn on the Google services (once)

```powershell
gcloud services enable run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com secretmanager.googleapis.com storage.googleapis.com
```

## Step 3. A place for server images (once)

The second command deletes old images automatically and keeps the two newest, so storage stays cheap.

```powershell
gcloud artifacts repositories create lumis --repository-format docker --location $REGION
gcloud artifacts repositories set-cleanup-policies lumis --location $REGION --policy deploy/cleanup-policy.json --no-dry-run
```

## Step 4. Two private buckets, and upload the model (once)

The upload is 1.7 GB, so it takes a few minutes.

```powershell
gcloud storage buckets create gs://$MODELS --location $REGION --uniform-bucket-level-access --public-access-prevention
gcloud storage buckets create gs://$UPLOADS --location $REGION --uniform-bucket-level-access --public-access-prevention
gcloud storage cp models/lumis_medsiglip_v3.onnx gs://$MODELS/
```

## Step 5. An identity for the backend with only the access it needs (once)

The backend runs as its own service account. It may read and write photos in the uploads bucket, and read the three
secrets. Nothing else.

```powershell
gcloud iam service-accounts create lumis-api --display-name "Lumis API"
gcloud storage buckets add-iam-policy-binding gs://$UPLOADS --member "serviceAccount:$SA" --role roles/storage.objectUser
```

## Step 6. Secrets (once)

The helper asks for each value with hidden typing, so nothing ends up on screen or in the terminal history.
The database address is read straight from the file `neon init` wrote, so it is never shown or pasted
(`DATABASE_URL` is Neon's pooled address, the right one for a server). For the Anthropic key, paste your Anthropic API key
(the one stored as `ANTHROPIC_API_KEY` in Colab's secrets; it powers the skin check).

```powershell
python deploy/set_secret.py lumis-jwt-secret --generate
python deploy/set_secret.py lumis-database-url --from-env-file ../.env.local --env-key DATABASE_URL
python deploy/set_secret.py lumis-anthropic-key
foreach ($s in "lumis-jwt-secret", "lumis-database-url", "lumis-anthropic-key") { gcloud secrets add-iam-policy-binding $s --member "serviceAccount:$SA" --role roles/secretmanager.secretAccessor }
```

## Step 7. Build the server image

Uploads the code (not the model, not `.env`, not your local database or photos), fetches the model from the
bucket, installs everything and checks the model file. About 5 to 10 minutes.

```powershell
gcloud builds submit --config cloudbuild.yaml --substitutions "_MODEL_BUCKET=$MODELS" .
```

## Step 8. Start the service

One long line. `--max-instances 2` caps how much can ever run at once, which also caps the cost.

```powershell
gcloud run deploy lumis-api --image $IMAGE --region $REGION --service-account $SA --allow-unauthenticated --cpu 8 --memory 4Gi --cpu-boost --execution-environment gen2 --concurrency 4 --min-instances 0 --max-instances 2 --timeout 120 --set-env-vars "IMAGE_BUCKET=$UPLOADS,CONTACT_EMAIL=$CONTACT" --set-secrets "DATABASE_URL=lumis-database-url:latest,JWT_SECRET=lumis-jwt-secret:latest,ANTHROPIC_API_KEY=lumis-anthropic-key:latest"
```

`--allow-unauthenticated` only means the address is reachable from the internet, which the app needs. Every
screening still requires a Lumis account.

## Step 9. Check that it works

```powershell
$URL = gcloud run services describe lumis-api --region $REGION --format "value(status.url)"
$URL
python scripts/smoke_test.py $URL --photo "C:\path\to\a_skin_photo.jpg"
```

The smoke test makes a temporary account, runs one screening, reads the stored photo back, then deletes
everything it made. It prints how long each step took, including the model's time on the server. Use a photo
you are allowed to use; it is handled exactly like a photo from the app (stored in your bucket, sent to
Anthropic for the skin check, then deleted by the test).

`$URL/docs` shows every endpoint in the browser.

## Step 10. Measure the model's speed on Cloud Run (for the report)

Runs the timing script on the same image and hardware, with three thread settings, without touching the service.

```powershell
gcloud run jobs deploy lumis-timing --image $IMAGE --region $REGION --cpu 8 --memory 4Gi --max-retries 0 --task-timeout 900 --command python --args="scripts/time_model.py,--threads,0,4,8,--runs,5"
gcloud run jobs execute lumis-timing --region $REGION --wait
gcloud run jobs logs read lumis-timing --region $REGION --limit 30 --order asc
```

To compare a smaller server, repeat with `--cpu 4`. If one thread setting is clearly fastest, add it to the service:
`gcloud run services update lumis-api --region $REGION --update-env-vars "ONNX_THREADS=8"`.

## Later

**After a code change:** run step 1, step 7 and step 8 again. Secrets, buckets and the database stay as they are.

**Demo or testing day (no cold start):** keep one instance warm, and switch it off again afterwards.

```powershell
gcloud run services update lumis-api --region $REGION --min-instances 1    # before
gcloud run services update lumis-api --region $REGION --min-instances 0    # after
```

**See what the server is doing:** `gcloud run services logs read lumis-api --region $REGION --limit 50`.
The logs show requests and the time per screening. They do not contain emails, photos or results.
The Cloud Run page in the console also has charts for request count, latency and errors.

**Go back to the previous version:** `gcloud run revisions list --service lumis-api --region $REGION`, then
`gcloud run services update-traffic lumis-api --region $REGION --to-revisions NAME=100`.

**Remove everything:** deleting the Google Cloud project stops all charges. Delete the Neon project separately.

## Costs (estimate from list prices on 2026-11-16, Singapore rates)

| What | Estimate |
|---|---|
| One screening (about 5 s on 8 CPUs) | about US$0.0014 |
| Cloud Run free allowance each month | worth about US$5, roughly 3,500 screenings |
| One cold start (about a minute of loading) | about US$0.02 |
| Keeping one instance warm (`--min-instances 1`) | about US$3 to US$4 **per day**: use it only on demo days |
| Image and model storage | well under US$1 a month |
| Neon database, free plan | US$0 (1 GB of storage) |

The warm-instance figure is higher than the US$0.65 a day in the original plan, because model v3 needs a much
larger server than v1 did. Prices: <https://cloud.google.com/run/pricing>.

## If something goes wrong

| Message | What to do |
|---|---|
| Build: `PERMISSION_DENIED` or `does not have storage.objects.get access` | Give the build account the standard build role, then run step 7 again: `$NUM = gcloud projects describe $PROJECT --format "value(projectNumber)"` and `gcloud projects add-iam-policy-binding $PROJECT --member "serviceAccount:${NUM}-compute@developer.gserviceaccount.com" --role roles/cloudbuild.builds.builder` |
| Build: `Model files are NOT ready` | The file in the models bucket is not the v3 model the config expects. Upload it again (step 4). |
| Deploy: `The user-provided container failed to start` | Read the reason with `gcloud run services logs read lumis-api --region $REGION --limit 50`. The backend says plainly what is missing (database, JWT secret, bucket or model file). |
| Deploy: quota or CPU limit error | Use `--cpu 4 --max-instances 1` in step 8. Slower per photo, but it runs. |
| Smoke test: first step is slow | That is the cold start. Run it again to see the normal speed. |
| Database errors right after a long quiet period | The Neon database was asleep and takes a few seconds to wake. Run the request again. |

## What is checked before a deploy can go wrong

- `python -m pytest -q` covers the server-only parts with stand-ins: production settings, bucket storage, and
  the whole API on a real PostgreSQL database when `TEST_DATABASE_URL` is set.
- The image build stops if the model file is missing or does not match its config.
- The backend refuses to start in production without PostgreSQL, a real JWT secret and a photo bucket.
