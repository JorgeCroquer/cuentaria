## Parent

[QUEN-930](https://cohetedigital.atlassian.net/browse/QUEN-930) — [PRD] Limpieza de imágenes huérfanas en S3

## What to build

A new cleanup handler in the `image-sync-lambda` repository that performs a weekly sweep of the S3 images bucket, identifying and soft-deleting orphaned images from the Content Manager (landing page and campaigns).

The handler (`cleanupHandler`) is exported as a second entry point alongside the existing sync handler. It performs the following end-to-end flow:

1. **Build the reference registry**: Fetch `landing/config.json` and `ecommerce/config.json` from the S3 config bucket. Recursively parse all fields to extract every image URL referenced in the landing page configuration and all campaign visual configs (all entries in the `visualConfig[]` array).

2. **List S3 objects**: Use `ListObjectsV2` to enumerate all objects in the images bucket under the content manager prefixes: `header/`, `home/`, `aboutus/`, `joinus/`, `footer/`, `contact/`, `award/`, `categories/`, `digital-magazine/`, and `campaigns/`.

3. **Identify orphans**: For each S3 object, check if its URL exists in the reference registry. If not, check its `LastModified` against the grace period (`GRACE_PERIOD_DAYS`, default 14). Objects within the grace period are skipped.

4. **Soft-delete or dry-run**: If `DRY_RUN=true` (default), log what would be moved. If `DRY_RUN=false`, move orphaned objects to `_trash/{original-key}` using `CopyObject` + `DeleteObject`.

5. **Log summary**: At the end, log a structured summary: total scanned, orphans found, within grace period (skipped), moved to trash (or would-move in dry-run).

Configuration is via environment variables: `DRY_RUN`, `GRACE_PERIOD_DAYS`, `LANDING_CONFIG_BUCKET`, `LANDING_CONFIG_PATH`, `ECOMMERCE_CONFIG_PATH`, `IMAGES_BUCKET`, `TRASH_PREFIX`.

## Acceptance criteria

- [ ] A `cleanupHandler` function is exported from the Lambda's entry point
- [ ] The handler fetches and parses `landing/config.json` to extract all referenced image URLs
- [ ] The handler fetches and parses `ecommerce/config.json` to extract all referenced image URLs from all `visualConfig[]` entries
- [ ] The handler lists all objects under the 10 content manager prefixes
- [ ] Objects whose URLs are in the reference registry are NOT marked as orphans
- [ ] Objects with `LastModified` within `GRACE_PERIOD_DAYS` are NOT marked as orphans (grace period protection)
- [ ] In `DRY_RUN=true` mode, orphans are logged but NOT moved
- [ ] In `DRY_RUN=false` mode, orphans are moved to `_trash/{original-key}` via `CopyObject` + `DeleteObject`
- [ ] A structured summary is logged at the end of each execution
- [ ] Unit tests cover: config JSON parsing, orphan detection logic, grace period filtering, dry-run vs. execution behavior
- [ ] The handler is independent of the existing sync handler (no shared mutable state)

## Blocked by

None — can start immediately (deployment requires INFRA slice for EventBridge schedule and IAM permissions).
