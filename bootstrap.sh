#!/bin/bash
set -euo pipefail

echo "=== Cloud Run Bootstrap (Cloud Shell) ==="

if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
  gcloud auth login
fi

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

PROJECT_ID="${PROJECT_ID:-}"
if [[ -z "${PROJECT_ID}" ]]; then
  PROJECT_ID="$(ask 'Enter NEW Project ID')"
fi
if [[ -z "${PROJECT_ID}" ]]; then
  echo "Project ID is required." >&2
  exit 1
fi

REGION="${REGION:-}"
if [[ -z "${REGION}" ]]; then
  mapfile -t REGION_LIST < <(gcloud run regions list --format="value(locationId)" | sort -u)
  PS3="Select a region (number): "
  select choice in "${REGION_LIST[@]}"; do
    if [[ -n "$choice" ]]; then
      REGION="$choice"
      break
    fi
  done
fi
echo "Using region: ${REGION}"

BILLING_ACCOUNT="${BILLING_ACCOUNT:-}"
if [[ -z "${BILLING_ACCOUNT}" ]]; then
  BILLING_ACCOUNT="$(gcloud billing accounts list --format="value(name)" --limit=1 || true)"
fi
if [[ -z "${BILLING_ACCOUNT}" ]]; then
  echo "No billing account found." >&2
  exit 1
fi
echo "Using billing account: ${BILLING_ACCOUNT}"

gcloud projects create "${PROJECT_ID}" || echo "Project may already exist."
gcloud billing projects link "${PROJECT_ID}" --billing-account="${BILLING_ACCOUNT}"
gcloud config set project "${PROJECT_ID}"

gcloud services enable   run.googleapis.com   iam.googleapis.com   serviceusage.googleapis.com   cloudresourcemanager.googleapis.com   artifactregistry.googleapis.com   cloudbuild.googleapis.com

SRC_DIR="${SRC_DIR:-}"
if [[ -z "${SRC_DIR}" ]]; then
  SRC_DIR="$(ask 'Enter path to folder with Dockerfile and source' '.')"
fi
if [[ ! -d "${SRC_DIR}" ]]; then
  echo "Source directory not found: ${SRC_DIR}" >&2
  exit 1
fi

REPO_NAME="${REPO_NAME:-myapp-repo}"
APP_NAME="${APP_NAME:-myapp}"
IMAGE_URI="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/${APP_NAME}"

gcloud artifacts repositories create "${REPO_NAME}"   --repository-format=docker   --location="${REGION}" || echo "Repo may already exist."

gcloud builds submit "${SRC_DIR}" --tag "${IMAGE_URI}"

gcloud run deploy "${APP_NAME}"   --image="${IMAGE_URI}"   --region="${REGION}"   --platform=managed   --allow-unauthenticated
