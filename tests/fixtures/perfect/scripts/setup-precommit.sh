#!/usr/bin/env bash
set -euo pipefail
pip install --user pre-commit
pre-commit install
pre-commit install --hook-type commit-msg
