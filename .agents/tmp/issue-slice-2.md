## Parent

[QUEN-930](https://cohetedigital.atlassian.net/browse/QUEN-930) — [PRD] Limpieza de imágenes huérfanas en S3

## What to build

Extend the eager delete pattern (established in the previous slice for Products) to Category and User image management.

**Categories**: The `Category` value object already has `setHeaderImage`, `clearHeaderImage`, `addCarouselImage`, `removeCarouselImage`, and `clearCarouselImages` methods. These methods need to emit domain events when images are removed (analogous to `ProductImageDeletedEvent`). A new `CategoryImageCleanupHandler` in the infrastructure layer listens to these events and calls `IStorageService.deleteFile`. Fire-and-forget: errors are logged as warnings.

**Users**: The IAM module handles user profile images. When a user's avatar/profile image is replaced or removed, a domain event should be emitted. A `UserImageCleanupHandler` listens and calls `deleteFile`. Same fire-and-forget pattern.

Both handlers follow the exact same pattern as `ProductImageCleanupHandler`: listen → deleteFile → catch + log warning on failure.

## Acceptance criteria

- [ ] Domain events exist for category image deletion (header image cleared, carousel image removed, all carousel images cleared)
- [ ] A `CategoryImageCleanupHandler` exists and listens to category image deletion events
- [ ] The handler calls `IStorageService.deleteFile` for each deleted image URL
- [ ] The handler is fire-and-forget (catches and logs errors without re-throwing)
- [ ] Domain event exists for user image deletion/replacement
- [ ] A `UserImageCleanupHandler` exists and follows the same fire-and-forget pattern
- [ ] Unit tests verify both handlers call deleteFile and swallow errors
- [ ] Existing category and user tests continue to pass

## Blocked by

- [QUEN-2457](https://cohetedigital.atlassian.net/browse/QUEN-2457) — BE: Extend IStorageService con deleteFile + Product Image Eager Delete
