#!/bin/bash
# ==========================================================
# Wrapper to automatically run bootstrap.sh in Cloud Shell
# ==========================================================

# Move into the folder containing this script (repo root)
cd "$(dirname "$0")"

# Run the main bootstrap script
bash bootstrap.sh
