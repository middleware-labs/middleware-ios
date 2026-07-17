# Middleware iOS dSYM upload

This folder wraps **`@middleware.io/sourcemap-uploader upload-dsym`**
([`/Users/…/code/sourcemap-uploader`](../../../../sourcemap-uploader) sibling
repo, or the published npm package).

Do **not** reimplement the SAS/PUT protocol here — all upload logic lives in
`sourcemap-uploader`.

## CLI

```bash
export MW_API_KEY="<your_rum_account_key>"

# Wrapper (resolves local checkout → npx)
./Tools/dsym-upload/upload-dsym.sh \
  --version "1.0.0" \
  --path "/path/to/YourApp.app.dSYM"

# Or call the package directly
npx @middleware.io/sourcemap-uploader upload-dsym \
  -k "$MW_API_KEY" \
  -av 1.0.0 \
  -p "/path/to/YourApp.app.dSYM"
```

### Local unpublished changes

If you are developing `sourcemap-uploader` next to this repo:

```bash
cd ~/code/sourcemap-uploader && npm run build
# wrappers auto-detect ~/code/sourcemap-uploader/dist/index.js

# or force a path:
export MW_SOURCEMAP_UPLOADER=~/code/sourcemap-uploader/dist/index.js
```

## Xcode Run Script

```bash
"${SRCROOT}/../../Tools/dsym-upload/xcode-upload-dsym.sh"
```

Set `MW_API_KEY` in the scheme / CI. Simulator builds are skipped unless
`MW_UPLOAD_SIMULATOR_DSYMS=1`.

## Version alignment

`--version` / `MARKETING_VERSION` must match the `app.version` attribute sent by
the Middleware iOS SDK.
