# Model files

The trained model is not stored in git. Two files go in this folder:

| File | In git? | Where it comes from |
|---|---|---|
| `lumis_model_config.json` | yes | `ml/09_export.ipynb` writes it to Drive: `Lumis/exports/model/` |
| `lumis_effb0_v1.onnx` (about 16 MB) | no | same Drive folder |

The config stores the ONNX file's SHA-256, and the backend refuses to start if the two do not match,
so an old model can never be served with new calibration settings (or the other way round).

Model v1: EfficientNet-B0 run `efficientnetb0_20261109_1427`, split v2, prior adjustment (training mix,
tau 0.75), temperature 1.3044, bands high >= 0.74, refer < 0.52, scabies capped at moderate.
Test results (one-time, 972 images): accuracy 65.5%, 76.1% when answering, 31.2% referred.
