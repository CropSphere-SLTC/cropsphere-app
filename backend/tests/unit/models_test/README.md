# models_test

- `test_loader.py` — unit tests for `app.models.loader.ModelLoader`. Covers `load_all` (pkl load, keras load, missing file, corrupt file, bundle split) and the `get_model`/`is_loaded`/`status_report` accessors. joblib and tensorflow are mocked.
