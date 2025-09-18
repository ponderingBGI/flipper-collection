# Unified test pipeline for all Flipper packages.

.PHONY: help lint build-all test

help:
	@echo "Flipper Collection Build Commands"
	@echo "================================="
	@echo "make lint       - Run ufbt lint for every app"
	@echo "make build-all  - Build all apps without using hardware"
	@echo "make test       - Lint and build all apps"
	@echo ""
	@echo "These commands rely on ufbt being available in your PATH."
	@echo "Install it with 'pip install ufbt' or by activating the repo's venv."

lint:
	python3 scripts/run_package_checks.py --skip-build

build-all:
	python3 scripts/run_package_checks.py --skip-lint

test:
	python3 scripts/run_package_checks.py
