#!/usr/bin/env bash
set -euo pipefail

# ------------ Host ports (used only by build_* scripts) ------------
EMBED_HOST_PORT=8006
LLAMA_HOST_PORT=8007
RERANK_HOST_PORT=8005
RIVA_HOST_PORT=8083

# ------------ Build scripts ------------
BUILD_EMBEDDING="./build_embedding.sh"
BUILD_LLAMA="./build_llama.sh"
BUILD_RERANK="./build_rerank.sh"
BUILD_RIVA="./build_riva.sh"

# ------------ Identify services ------------
ALLOWED_EMBED=("nvcr.io/nim/nvidia/llama-3.2-nv-embedqa")
ALLOWED_LLAMA=("nvcr.io/nim/meta/llama-3.1-8b-instruct")
ALLOWED_RERANK=("nvcr.io/nim/nvidia/llama-3.2-nv-rerankqa")
ALLOWED_RIVA=("riva")  # broad match

# Known container names (so we can restart even if image match fails)
EMBED_NAMES=("embed-server")
LLAMA_NAMES=("llama-server")
RERANK_NAMES=("rerank-server")
RIVA_NAMES=("parakeet-ctc-asr" "riva-server")  # <- includes your existing name

# ------------ Probe config ------------
POLL_SECS=${POLL_SECS:-5}
LLAMA_MODEL="${LLAMA_MODEL:-meta/llama-3.1-8b-instruct}"

# ------------ Persistent caches on host ------------
CACHE_DIR="${CACHE_DIR:-$HOME/.cache/nim}"
LLAMA_CACHE="${LLAMA_CACHE:-$CACHE_DIR/llama}"
EMBED_CACHE="${EMBED_CACHE:-$CACHE_DIR/embed}"
RERANK_CACHE="${RERANK_CACHE:-$CACHE_DIR/rerank}"
RIVA_CACHE="${RIVA_CACHE:-$CACHE_DIR/riva}"
COMMON_CACHE="${COMMON_CACHE:-$CACHE_DIR/common}"   # optional: /root/.cache

mkdir -p "$LLAMA_CACHE" "$EMBED_CACHE" "$RERANK_CACHE" "$RIVA_CACHE" "$COMMON_CACHE"
export CACHE_DIR LLAMA_CACHE EMBED_CACHE RERANK_CACHE RIVA_CACHE COMMON_CACHE
export EMBED_HOST_PORT LLAMA_HOST_PORT RERANK_HOST_PORT RIVA_HOST_PORT

# ------------ Load NGC API key from .env ------------
ENV_FILE="${ENV_FILE:-.env}"
NGC_API_KEY=""
if [[ -f "$ENV_FILE" ]]; then
  raw="$(grep -E -m1 '^export[[:space:]]+NGC_API_KEY=' "$ENV_FILE" || true)"
  if [[ -n "$raw" ]]; then
    NGC_API_KEY="${raw#*=}"
    NGC_API_KEY="${NGC_API_KEY%\"}"; NGC_API_KEY="${NGC_API_KEY#\"}"
    NGC_API_KEY="${NGC_API_KEY%\'}"; NGC_API_KEY="${NGC_API_KEY#\'}"
    echo "🔑 Loaded NGC_API_KEY from $ENV_FILE"
  fi
fi
export NGC_API_KEY
CURL_AUTH=(); [[ -n "${NGC_API_KEY}" ]] && CURL_AUTH=(-H "Authorization: Bearer ${NGC_API_KEY}")

# ------------ Helpers ------------
need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }; }
need_cmd curl; need_cmd docker; need_cmd bash
hr(){ printf '%*s\n' "$(tput cols 2>/dev/null || echo 80)" '' | tr ' ' -; }

image_matches_any() {
  local image="$1"; shift
  for p in "$@"; do [[ "$image" == *"$p"* ]] && return 0; done
  return 1
}

find_existing_container_by_image() {
  local -a patterns=("$@")
  local cid image
  for cid in $(docker ps -a -q); do
    image="$(docker inspect -f '{{.Config.Image}}' "$cid" 2>/dev/null || true)"
    [[ -n "$image" ]] || continue
    if image_matches_any "$image" "${patterns[@]}"; then
      echo "$cid"; return 0
    fi
  done
  return 1
}

find_existing_container_by_names() {
  local -a names=("$@")
  local cid nm
  while read -r line; do
    cid="${line%% *}"; nm="${line#* }"
    for want in "${names[@]}"; do
      if [[ "$nm" == "$want" ]]; then
        echo "$cid"; return 0
      fi
    done
  done < <(docker ps -a --format '{{.ID}} {{.Names}}')
  return 1
}

start_container_idempotent() {
  local cid="$1"
  local status
  status="$(docker inspect -f '{{.State.Status}}' "$cid" 2>/dev/null || echo '')"
  if [[ "$status" == "running" ]]; then
    docker restart "$cid" >/dev/null
  else
    docker start "$cid" >/dev/null
  fi
}

# ---- Llama probe with endpoint autodetection (no timeout) ----
probe_llama_until_ready() {
  local base="http://localhost:${LLAMA_HOST_PORT}"
  echo "⏳ Probing Llama on ${base} …"
  local -a CAND=(
    "/v1/chat/completions|{\"model\":\"${LLAMA_MODEL}\",\"messages\":[{\"role\":\"user\",\"content\":\"ping\"}],\"max_tokens\":1}|\"choices\""
    "/v1/completions|{\"model\":\"${LLAMA_MODEL}\",\"prompt\":\"ping\",\"max_tokens\":1}|\"choices\""
    "/v1/generate|{\"model\":\"${LLAMA_MODEL}\",\"prompt\":\"ping\",\"max_tokens\":1}|\"text\""
  )
  while true; do
    for entry in "${CAND[@]}"; do
      local path="${entry%%|*}"; local rest="${entry#*|}"
      local body="${rest%%|*}"; local expect="${rest##*|}"
      local resp code
      resp="$(curl -sS -X POST -H 'Content-Type: application/json' "${CURL_AUTH[@]}" -d "$body" "${base}${path}" || true)"
      code="$(curl -sS -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' "${CURL_AUTH[@]}" -d "$body" "${base}${path}" || echo 000)"
      if [[ "$code" == "200" && "$resp" == *"$expect"* ]]; then
        echo "✅ Llama ready via POST ${path}"
        return 0
      fi
    done
    echo "…not ready, retrying in ${POLL_SECS}s"
    sleep "$POLL_SECS"
  done
}

run_step() {
  local name="$1" script="$2"
  shift 2
  # first array: image patterns; second array: known names
  # shellcheck disable=SC2206
  local patterns=(${1}); shift
  # shellcheck disable=SC2206
  local known_names=(${1:-}); shift || true

  hr; echo "▶️  $name"

  local cid=""
  # 1) Prefer by image
  if cid="$(find_existing_container_by_image "${patterns[@]}")"; then
    echo "🔄 Found existing $name container by image ($cid). Restarting with saved ports…"
    start_container_idempotent "$cid"
    echo "✅ $name is up ($cid)."
    return 0
  fi

  # 2) Else, try by known names (covers '/parakeet-ctc-asr' case)
  if [[ "${#known_names[@]}" -gt 0 ]] && cid="$(find_existing_container_by_names "${known_names[@]}")"; then
    echo "🔄 Found existing $name container by name ($cid). Restarting with saved ports…"
    start_container_idempotent "$cid"
    echo "✅ $name is up ($cid)."
    return 0
  fi

  # 3) Otherwise, build/pull fresh (this defines ports via -p and mounts caches)
  echo "🔧 No existing $name container. Building/pulling via $script …"
  bash "$script"
}

# ------------ Orchestration ------------
main() {
  hr; echo "🚀 Orchestration starting"

  # NOTE: each build_* must mount caches:
  #  -v "${<SERVICE>_CACHE}:/models"  -v "${COMMON_CACHE}:/root/.cache"

  run_step "Embedding" "$BUILD_EMBEDDING" "${ALLOWED_EMBED[*]}" "${EMBED_NAMES[*]}"
  run_step "Llama"     "$BUILD_LLAMA"     "${ALLOWED_LLAMA[*]}" "${LLAMA_NAMES[*]}"
  echo "⏱  Checking Llama readiness …"
  probe_llama_until_ready
  run_step "Rerank"    "$BUILD_RERANK"    "${ALLOWED_RERANK[*]}" "${RERANK_NAMES[*]}"
  run_step "Riva"      "$BUILD_RIVA"      "${ALLOWED_RIVA[*]}"   "${RIVA_NAMES[*]}"

  hr; echo "🧩 docker compose up -d …"
  docker compose up -d

  hr; echo "🌐 Launching browser at http://localhost:9100"
  if command -v xdg-open >/dev/null; then
    xdg-open "http://localhost:9100" >/dev/null 2>&1 &
  elif command -v open >/dev/null; then
    open "http://localhost:9100" >/dev/null 2>&1 &
  else
    echo "ℹ️  Open http://localhost:9100 manually."
  fi

  hr; echo "✅ Done."
}

main "$@"
