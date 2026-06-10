## Parent

[QUEN-930](https://cohetedigital.atlassian.net/browse/QUEN-930) — [PRD] Limpieza de imágenes huérfanas en S3

## What to build

Extend the Content Manager sweep (from the previous slice) to also cover product, category, and user images by querying the backend API for referenced image URLs.

This slice adds a second source of truth to the sweep's reference registry:

1. **Product images**: Paginate through `GET /products` (using the existing `productApi` service in the Lambda), extracting `imageUrls[]` from each product. Build a set of all referenced product image URLs.

2. **Category images**: Call `GET /categories`, extracting `headerImageUrl` and `carouselImagesUrls[]` from each category.

3. **User images**: Call the appropriate user endpoint to extract avatar/profile image URLs (if applicable).

4. **Extended prefix scan**: Add `products/`, `categories/`, and `users/` to the list of S3 prefixes scanned by `ListObjectsV2`.

5. **Orphan detection**: Apply the same logic as the Content Manager sweep — cross-reference S3 objects against the combined registry (config JSONs + API data), respect grace period, and soft-delete to `_trash/`.

The sweep should handle API pagination correctly (products endpoint returns paginated results) and be resilient to API failures (if the backend is unreachable, skip the API-based prefixes and log a warning rather than failing the entire sweep).

## Acceptance criteria

- [ ] The sweep fetches all products from `GET /products` by paginating through all pages
- [ ] Product `imageUrls[]` are included in the reference registry
- [ ] The sweep fetches all categories from `GET /categories`
- [ ] Category `headerImageUrl` and `carouselImagesUrls[]` are included in the reference registry
- [ ] The sweep scans `products/`, `categories/`, and `users/` prefixes in addition to content manager prefixes
- [ ] Orphan detection, grace period, dry-run, and soft-delete work identically for these new prefixes
- [ ] If the backend API is unreachable, the sweep skips API-based prefixes and logs a warning (does NOT fail entirely)
- [ ] The structured summary log includes counts for the new prefixes
- [ ] Unit tests cover: API pagination, resilience to API failures, correct registry building from API responses

## Blocked by

- [QUEN-2459](https://cohetedigital.atlassian.net/browse/QUEN-2459) — LAMBDA: Content Manager Sweep — Landing Page + Campañas
