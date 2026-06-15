#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${OUT_DIR:-build/web}"

if [[ -z "${GODOT_BIN:-}" ]]; then
	if command -v godot >/dev/null 2>&1; then
		GODOT_BIN="$(command -v godot)"
	else
		GODOT_BIN="/home/lichdandy/.local/bin/godot"
	fi
fi

rm -rf "${ROOT_DIR:?}/${OUT_DIR}"
mkdir -p "${ROOT_DIR}/${OUT_DIR}"

"${GODOT_BIN}" --headless --path "${ROOT_DIR}" --export-release Web "${ROOT_DIR}/${OUT_DIR}/index.html"

printf 'Godot Web export ready: %s\n' "${ROOT_DIR}/${OUT_DIR}"
