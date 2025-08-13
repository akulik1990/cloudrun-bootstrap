#!/bin/bash
set -euo pipefail

# ==========================================================
# Cloud Run Bootstrap (Docker Hub only)
# ----------------------------------------------------------
# This script interactively deploys a public Docker Hub
# image to a new or existing Cloud Run service.
#
# NOTES:
#  - Run this in Google Cloud Shell. It already has gcloud.
#  - You do NOT need Docker Desktop or any local installs.
# ==========================================================

echo "=== Cloud Run Bootstrap (Docker Hub) ==="

# 1) Authentication and setup
echo "Checking gcloud authentication..."
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
  echo "No active gcloud account found. Launching login..."
  gcloud auth login
fi

# Helper: ask with default
ask() {
  local prompt="$1"
  local default="${2:-}"
  local var
  if [[ -n "$default" ]]; then
    read -r -p "$prompt [$default]: " var
    echo "${var:-$default}"
  else
    read -r -p "$prompt: " var
    echo "$var"
  fi
}

# 2) Project ID
PROJECT_ID="$(ask 'Enter a new or existing GCP Project ID')"
if [[ -z "${PROJECT_ID}" ]]; then
  echo "Project ID is required." >&2
  exit 1
fi
gcloud config set project "${PROJECT_ID}"

# 3) Region selection
echo "Fetching available Cloud Run regions..."
mapfile -t REGION_LIST < <(gcloud run regions list --format="value(locationId)" | sort -u)
if [[ ${#REGION_LIST[@]} -eq 0 ]]; then
  echo "No regions returned. Check your gcloud configuration and permissions." >&2
  exit 1
fi
PS3="Select a region (number): "
select choice in "${REGION_LIST[@]}"; do
  if [[ -n "$choice" ]]; then
    REGION="$choice"
    break
  fi
done
echo "Using region: ${REGION}"

# 4) Billing account (auto-detect)
echo "Detecting billing account..."
BILLING_ACCOUNT="$(gcloud billing accounts list --format="value(name)" --limit=1 || true)"
if [[ -z "${BILLING_ACCOUNT}" ]]; then
  echo "No billing account found. Please set one up in GCP Console (Billing) and re-run." >&2
  exit 1
fi
echo "Using billing account: ${BILLING_ACCOUNT}"

# 5) Create project & link billing
echo "Creating project: ${PROJECT_ID} (ignoring error if exists)..."
if ! gcloud projects describe "${PROJECT_ID}" &>/dev/null; then
  gcloud projects create "${PROJECT_ID}"
  echo "Linking billing..."
  gcloud billing projects link "${PROJECT_ID}" --billing-account="${BILLING_ACCOUNT}"
else
  echo "Project already exists."
fi

# 6) Enable required APIs
echo "Enabling required APIs..."
gcloud services enable \
  run.googleapis.com \
  iam.googleapis.com \
  serviceusage.googleapis.com \
  cloudresourcemanager.googleapis.com

# 7) Get Docker Hub image name and Cloud Run service name
DOCKER_HUB_IMAGE="$(ask 'Enter public Docker Hub image name (e.g., nginx:latest)')"
if [[ -z "${DOCKER_HUB_IMAGE}" ]]; then
  echo "A Docker Hub image name is required." >&2
  exit 1
fi
echo "Using Docker Hub image: ${DOCKER_HUB_IMAGE}"

APP_NAME="$(ask 'Enter Cloud Run service name' 'myapp')"

# 8) Deploy to Cloud Run
echo "Deploying service ${APP_NAME} from Docker Hub image ${DOCKER_HUB_IMAGE} to Cloud Run..."
gcloud run deploy "${APP_NAME}" \
  --image "${DOCKER_HUB_IMAGE}" \
  --region "${REGION}" \
  --allow-unauthenticated \
  --platform managed

echo "Deployment complete!"
echo "Service URL:"
gcloud run services describe "${APP_NAME}" \
  --region "${REGION}" \
  --format="value(status.url)"
