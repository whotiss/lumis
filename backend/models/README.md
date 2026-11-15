# Model files

The app uses **model v3** (MedSigLIP image encoder + small classifier, `ml/19_final_v3.ipynb`).
Model v1 (EfficientNet-B0) is kept so the two can be compared.

| File | In git? | Where it comes from |
|---|---|---|
| `lumis_model_config_v3.json` | yes | Drive `Lumis/exports/model_v3/` (notebook 19, PIL note added by notebook 20) |
| `lumis_head_v3.npz` (1.2 MB) | yes | same Drive folder: scaler, PCA and logistic regression arrays |
| `photo_check_v3.json` | yes | same Drive folder, without the v1 measurements that file carried |
| `lumis_medsiglip_v3.onnx` (1.71 GB) | **no** (too big for git) | same Drive folder: download it into this folder |
| `lumis_model_config.json`, `photo_check.json` | yes | v1, Drive `Lumis/exports/model/` |
| `lumis_effb0_v1.onnx` (16 MB) | no | v1, same Drive folder |
| `claude_check.json` | yes | notebook 15 (skin gate on, full check off) |

The config stores the ONNX file's SHA-256, and the backend refuses to start if the two do not match,
so an old model can never be served with new calibration settings (or the other way round). It also refuses
a photo check file that was set for a different model.

**Which model runs** is set in `backend/.env` (default v3):
```
MODEL_CONFIG_FILE=lumis_model_config_v3.json     # v1: lumis_model_config.json
PHOTO_CHECK_FILE=photo_check_v3.json             # v1: photo_check.json
```

**Model v3:** trained on DermNet train + SCIN train/validation + extra SCIN cases; prior adjustment as v1;
temperature 1.0073; bands high >= 0.64, refer < 0.20 (so nothing is referred); scabies never high.
One-time test: SCIN phone photos (121 cases) accuracy 69.4%, average sensitivity 65.7%; DermNet test (972)
accuracy 70.4%. The 8-bit version was tested in notebook 20 and not adopted (changed too many results).

**On the server:** the 1.71 GB file is uploaded once to a private Cloud Storage bucket and built into the server
image from there (`cloudbuild.yaml`); the build fails if it does not match the config. See `deploy/README.md`.

**Speed:** the encoder takes about 11 s per photo on Colab's 2 CPU cores. Measure it on any computer with
`python scripts/time_model.py` (see the script for options); every screening response also carries a
`Server-Timing` header with the time of each step.
