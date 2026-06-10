## Parent

[QUEN-930](https://cohetedigital.atlassian.net/browse/QUEN-930) — [PRD] Limpieza de imágenes huérfanas en S3

## What to build

End-to-end eager deletion of product images from S3 when they are removed via the backoffice.

This slice has two parts:

1. **Extend the storage port**: Add a `deleteFile(fileUrl: string): Promise<void>` method to the `IStorageService` interface and implement it in `S3Service` using `DeleteObjectCommand`. The implementation should extract the S3 key from the full URL and execute the delete against the configured images bucket.

2. **Wire the event handler**: Create a `ProductImageCleanupHandler` in the infrastructure layer of the Product module. This handler listens to the existing `ProductImageDeletedEvent` domain event and calls `IStorageService.deleteFile` with the deleted image URL. The handler MUST be fire-and-forget: if the S3 delete fails, it logs a warning and does NOT propagate the error. The user's operation (removing the image reference from the product) must always succeed regardless of S3 cleanup outcome.

The `ProductImageDeletedEvent` already contains the `imageUrl` of the deleted image and is emitted by `Product.removeImageUrl()` and `Product.removeAllImages()`.

## Acceptance criteria

- [ ] `IStorageService` interface includes a `deleteFile(fileUrl: string): Promise<void>` method
- [ ] `S3Service` implements `deleteFile` using `DeleteObjectCommand`, correctly extracting the S3 key from the image URL
- [ ] A `ProductImageCleanupHandler` exists in the Product module's infrastructure layer
- [ ] The handler listens to `ProductImageDeletedEvent` and invokes `deleteFile`
- [ ] If `deleteFile` throws, the handler catches the error, logs a warning, and does NOT re-throw
- [ ] Unit test: `S3Service.deleteFile` invokes `DeleteObjectCommand` with the correct bucket and key
- [ ] Unit test: `ProductImageCleanupHandler` calls `deleteFile` and swallows errors gracefully
- [ ] Existing product tests continue to pass

## Blocked by

None — can start immediately.
