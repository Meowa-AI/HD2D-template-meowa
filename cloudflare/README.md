# WebGL R2 Deployment

HD2D uses the same shared hosting split as the other games:

```text
game.meowa.ai/hd2d/
game-assets.meowa.ai/hd2d/releases/<BUILD_VERSION>/
```

`game.meowa.ai` is the Cloudflare Pages project root shared by all games.
`game-assets.meowa.ai` is the R2 custom domain/CDN for versioned runtime files.
This repo only owns the `hd2d/` subdirectory and must not overwrite the shared
Pages `_worker.js`.

## Build

```bash
tools/export_web.sh
python3 tools/serve_web.py --dir build/web
```

Open `http://127.0.0.1:8062/` for a local smoke test.

## Build And Deploy

```bash
R2_BUCKET=meowa-game-assets \
GAME_ASSETS_BASE_URL=https://game-assets.meowa.ai \
GAME_SITE_ROOT=../game-site-root/game-meowa-ai \
tools/deploy_cloudflare.sh
```

The script:

1. Exports the Godot Web Compatibility build to `build/web`.
2. Uploads versioned runtime files to
   `r2://meowa-game-assets/hd2d/releases/<BUILD_VERSION>/`.
3. Generates `output/web-entrypoint/hd2d/`.
4. Rewrites `GODOT_CONFIG.executable` to the R2 CDN runtime prefix.
5. Copies the lightweight entrypoint into `$GAME_SITE_ROOT/hd2d/`.
6. Deploys the full shared Pages root to project `game-meowa-ai`.

The current Godot export has a large `index.wasm` and a small `index.pck`.
By default the wasm and worklet runtime files are fetched from R2, while
`index.pck` remains in the Pages entrypoint. Set `REMOTE_PACK=1` if the PCK
later grows beyond the Pages single-file limit.

## Dry Run

Build and generate the entrypoint without uploading or deploying:

```bash
SKIP_DEPLOY=1 tools/deploy_cloudflare.sh
```

Use an existing export without rebuilding:

```bash
SKIP_GODOT_EXPORT=1 SKIP_DEPLOY=1 tools/deploy_cloudflare.sh
```

Only generate the entrypoint:

```bash
SKIP_GODOT_EXPORT=1 \
SKIP_R2_UPLOAD=1 \
DEPLOY_ENTRYPOINT_TO_PAGES=0 \
tools/deploy_cloudflare.sh
```

## First-Time R2 CORS

`game.meowa.ai` loads runtime files from `game-assets.meowa.ai`, so R2 must allow
that origin:

```bash
APPLY_R2_CORS=1 \
SKIP_GODOT_EXPORT=1 \
SKIP_R2_UPLOAD=1 \
DEPLOY_ENTRYPOINT_TO_PAGES=0 \
R2_CORS_ALLOWED_ORIGINS=https://game.meowa.ai,https://game-meowa-ai.pages.dev \
tools/deploy_cloudflare.sh
```

## Parameters

- `R2_BUCKET`: R2 bucket name, default `meowa-game-assets`.
- `GAME_SLUG`: public slug, default `hd2d`.
- `GAME_ASSETS_BASE_URL`: R2 CDN root, default `https://game-assets.meowa.ai`.
- `GAME_SITE_ROOT`: shared Pages publish root, default
  `../game-site-root/game-meowa-ai`.
- `PAGES_PROJECT`: Cloudflare Pages project, default `game-meowa-ai`.
- `BUILD_VERSION`: version folder, default UTC timestamp plus git short SHA.
- `R2_PREFIX`: object prefix, default `hd2d/releases/$BUILD_VERSION`.
- `REMOTE_PACK=1`: also load `index.pck` from R2 instead of Pages.
- `SKIP_GODOT_EXPORT=1`: use an existing `build/web`.
- `SKIP_R2_UPLOAD=1`: skip R2 upload.
- `DEPLOY_ENTRYPOINT_TO_PAGES=0`: do not copy into `$GAME_SITE_ROOT`.
- `SKIP_PAGES_DEPLOY=1`: copy into `$GAME_SITE_ROOT` but do not deploy Pages.
- `SKIP_DEPLOY=1`: skip R2 upload, Pages copy, and Pages deploy.
