#!/usr/bin/env bash
set -Eeuo pipefail

LOG_FILE="/workspace/vast-bootstrap.log"
mkdir -p /workspace
exec > >(tee -a "$LOG_FILE") 2>&1

info(){ echo "[BOOTSTRAP] $(date '+%H:%M:%S') $*"; }
fail(){ echo "[BOOTSTRAP][ERROR] $(date '+%H:%M:%S') $*" >&2; }

: "${WORKSPACE:=/workspace}"
: "${PRIVATE_REPO_OWNER:?PRIVATE_REPO_OWNER fehlt}"
: "${PRIVATE_REPO_NAME:?PRIVATE_REPO_NAME fehlt}"
: "${PRIVATE_REPO_REF:=main}"
: "${GITHUB_PAT:?GITHUB_PAT fehlt}"

API_BASE="https://api.github.com/repos/${PRIVATE_REPO_OWNER}/${PRIVATE_REPO_NAME}/contents"
AUTH_HEADER="Authorization: Token ${GITHUB_PAT}"
ACCEPT_HEADER="Accept: application/vnd.github.raw+json"

fetch_private_file() {
  local repo_path="$1" dest="$2"
  mkdir -p "$(dirname "$dest")"
  info "Hole ${repo_path}"
  curl -fsSL \
    -H "$AUTH_HEADER" \
    -H "$ACCEPT_HEADER" \
    "${API_BASE}/${repo_path}?ref=${PRIVATE_REPO_REF}" \
    -o "$dest"
}

fetch_private_file "provisioning.sh" "$WORKSPACE/provisioning.sh"
fetch_private_file "model-list.sh" "$WORKSPACE/model-list.sh"
fetch_private_file "configs/config.json" "$WORKSPACE/config.json"
fetch_private_file "configs/ui-config.json" "$WORKSPACE/ui-config.json"

chmod +x "$WORKSPACE/provisioning.sh" "$WORKSPACE/model-list.sh"
exec "$WORKSPACE/provisioning.sh"
