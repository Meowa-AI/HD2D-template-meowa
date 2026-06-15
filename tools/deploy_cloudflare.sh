#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GAME_SLUG="${GAME_SLUG:-hd2d}"
R2_BUCKET="${R2_BUCKET:-meowa-game-assets}"
GAME_ASSETS_BASE_URL="${GAME_ASSETS_BASE_URL:-https://game-assets.meowa.ai}"
GAME_SITE_ROOT="${GAME_SITE_ROOT:-${ROOT_DIR}/../game-site-root/game-meowa-ai}"
PAGES_PROJECT="${PAGES_PROJECT:-game-meowa-ai}"
WEB_EXPORT_DIR="${WEB_EXPORT_DIR:-build/web}"
WEB_ENTRYPOINT_DIR="${WEB_ENTRYPOINT_DIR:-output/web-entrypoint/${GAME_SLUG}}"
BUILD_VERSION="${BUILD_VERSION:-$(date -u +%Y%m%d%H%M%S)-$(git -C "${ROOT_DIR}" rev-parse --short HEAD 2>/dev/null || printf local)}"
R2_PREFIX="${R2_PREFIX:-${GAME_SLUG}/releases/${BUILD_VERSION}}"
REMOTE_PACK="${REMOTE_PACK:-0}"
APPLY_R2_CORS="${APPLY_R2_CORS:-0}"
R2_CORS_ALLOWED_ORIGINS="${R2_CORS_ALLOWED_ORIGINS:-https://game.meowa.ai,https://game-meowa-ai.pages.dev}"

cd "${ROOT_DIR}"

if command -v wrangler >/dev/null 2>&1; then
	WRANGLER=(wrangler)
else
	WRANGLER=(npx --yes wrangler@latest)
fi

content_type_for() {
	case "$1" in
		*.html) echo "text/html; charset=utf-8" ;;
		*.js) echo "application/javascript; charset=utf-8" ;;
		*.wasm) echo "application/wasm" ;;
		*.pck) echo "application/octet-stream" ;;
		*.png) echo "image/png" ;;
		*.jpg|*.jpeg) echo "image/jpeg" ;;
		*.svg) echo "image/svg+xml" ;;
		*) echo "application/octet-stream" ;;
	esac
}

upload_asset() {
	local file="$1"
	local rel="${file#${WEB_EXPORT_DIR}/}"
	local key="${R2_PREFIX}/${rel}"

	if [[ ! -f "${file}" ]]; then
		return
	fi

	"${WRANGLER[@]}" r2 object put "${R2_BUCKET}/${key}" \
		--remote \
		--file "${file}" \
		--content-type "$(content_type_for "${file}")" \
		--cache-control "public, max-age=31536000, immutable"
}

apply_r2_cors() {
	local cors_file
	cors_file="$(mktemp)"
	python3 - "${R2_CORS_ALLOWED_ORIGINS}" "${cors_file}" <<'PY'
import json
import sys

origins = [origin.strip() for origin in sys.argv[1].split(",") if origin.strip()]
payload = [
    {
        "AllowedOrigins": origins,
        "AllowedMethods": ["GET", "HEAD"],
        "AllowedHeaders": ["*"],
        "ExposeHeaders": ["ETag"],
        "MaxAgeSeconds": 86400,
    }
]
with open(sys.argv[2], "w", encoding="utf-8") as handle:
    json.dump(payload, handle, indent=2)
    handle.write("\n")
PY
	"${WRANGLER[@]}" r2 bucket cors set "${R2_BUCKET}" --file "${cors_file}" --force
	rm -f "${cors_file}"
}

if [[ "${SKIP_EXPORT:-0}" != "1" && "${SKIP_GODOT_EXPORT:-0}" != "1" ]]; then
	tools/export_web.sh
fi

if [[ ! -f "${WEB_EXPORT_DIR}/index.html" ]]; then
	echo "Missing ${WEB_EXPORT_DIR}/index.html. Run tools/export_web.sh first." >&2
	exit 1
fi

if [[ "${APPLY_R2_CORS}" == "1" ]]; then
	apply_r2_cors
fi

if [[ "${SKIP_DEPLOY:-0}" != "1" && "${SKIP_R2_UPLOAD:-0}" != "1" ]]; then
	upload_asset "${WEB_EXPORT_DIR}/index.js"
	upload_asset "${WEB_EXPORT_DIR}/index.wasm"
	upload_asset "${WEB_EXPORT_DIR}/index.audio.worklet.js"
	upload_asset "${WEB_EXPORT_DIR}/index.audio.position.worklet.js"
	upload_asset "${WEB_EXPORT_DIR}/index.pck"
	while IFS= read -r -d '' side_wasm; do
		upload_asset "${side_wasm}"
	done < <(find "${WEB_EXPORT_DIR}" -maxdepth 1 -type f -name '*.side.wasm' -print0)
	echo "Uploaded runtime assets to r2://${R2_BUCKET}/${R2_PREFIX}/"
fi

entrypoint_args=(
	--web-export-dir "${WEB_EXPORT_DIR}"
	--entrypoint-dir "${WEB_ENTRYPOINT_DIR}"
	--game-slug "${GAME_SLUG}"
	--build-version "${BUILD_VERSION}"
	--assets-base-url "${GAME_ASSETS_BASE_URL}"
	--r2-prefix "${R2_PREFIX}"
)
if [[ "${REMOTE_PACK}" == "1" ]]; then
	entrypoint_args+=(--remote-pack)
fi
python3 tools/build_cloudflare_entrypoint.py "${entrypoint_args[@]}"

copied_to_pages=0
if [[ "${SKIP_DEPLOY:-0}" != "1" && "${DEPLOY_ENTRYPOINT_TO_PAGES:-1}" != "0" ]]; then
	mkdir -p "${GAME_SITE_ROOT}"
	rm -rf "${GAME_SITE_ROOT:?}/${GAME_SLUG}"
	mkdir -p "${GAME_SITE_ROOT}/${GAME_SLUG}"
	cp -a "${WEB_ENTRYPOINT_DIR}/." "${GAME_SITE_ROOT}/${GAME_SLUG}/"
	copied_to_pages=1

	if [[ ! -f "${GAME_SITE_ROOT}/_worker.js" ]]; then
		echo "Warning: ${GAME_SITE_ROOT}/_worker.js is missing; HD2D did not create one because this Pages root is shared." >&2
	fi

	if [[ "${SKIP_PAGES_DEPLOY:-0}" != "1" ]]; then
		"${WRANGLER[@]}" pages deploy "${GAME_SITE_ROOT}" --project-name "${PAGES_PROJECT}"
	fi
fi

echo "Generated entrypoint: ${ROOT_DIR}/${WEB_ENTRYPOINT_DIR}/"
if [[ "${copied_to_pages}" == "1" ]]; then
	echo "Pages entrypoint: ${GAME_SITE_ROOT}/${GAME_SLUG}/"
fi
echo "Public URL: https://game.meowa.ai/${GAME_SLUG}/"
echo "R2 runtime prefix: ${GAME_ASSETS_BASE_URL%/}/${R2_PREFIX}/"
