# Development Workflow

This repo uses uFBT for a mainstream Flipper app workflow.

## Prerequisites
- Python 3 installed
- `pip install --upgrade ufbt` (or use the included `venv`)

## Build & Test (local)
The repository includes an automated pipeline that runs static checks and
compiles every app without requiring a physical Flipper device.

1. Ensure the `ufbt` CLI is installed (`pip install ufbt`) or activate the
   project's virtual environment.
2. From the repository root, run one of the helper targets:
   - `make lint` – run `ufbt lint` for every app.
   - `make build-all` – compile all apps (`ufbt build`).
   - `make test` – execute lint + build in sequence (recommended for PRs).
3. Optional: for manual device validation after the pipeline passes, launch to
   the Flipper over USB from an individual app directory with `ufbt launch`.

## Pull Requests
- CI builds for dev & release and runs `ufbt lint`.
- Fix any CI failures before requesting review.

## Packaging
- On merge to `main`, GitHub Actions builds the app and places the packaged `.fap` under `packages/apps/Tools/`.
- Root README links to these folders for easy drag-and-drop onto the Flipper.
