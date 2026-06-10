h2. Problem Statement

Quenova almacena todas las imágenes del sistema (landing page, ecommerce, productos, categorías, usuarios) en un bucket S3 compartido. Cuando un usuario de Quenova modifica el contenido visual de la plataforma — cambia un banner, reemplaza un logo, actualiza fotos de producto — las imágenes anteriores quedan *huérfanas* en S3: la URL se sobreescribe en la configuración o en la BD, pero el archivo binario permanece en el bucket indefinidamente.

No existe ningún mecanismo de borrado. En el código del backoffice, hay múltiples funciones {{deleteImage}} y {{DeleteObjectCommand}} que fueron implementadas pero luego *comentadas*. El módulo Terraform de S3 no tiene lifecycle rules. El backend no expone operaciones de borrado de archivos en su {{IStorageService}}.

El resultado es un bucket que crece monotónicamente con cada cambio de contenido, acumulando costos de storage innecesarios y dificultando la gobernanza de los activos digitales.

h2. Solution

Implementar una estrategia de limpieza en dos capas complementarias:

*Capa 1 — Eager Delete (borrado inmediato)*: Para entidades con gestión de imágenes en el dominio del backend (Product, Category, User), reaccionar a los domain events de borrado de imagen con un handler fire-and-forget que elimina la imagen de S3 en el momento en que se quita la referencia.

*Capa 2 — Weekly Sweep (barrido batch)*: Una Lambda scheduled que semanalmente cruza las imágenes existentes en S3 contra las URLs referenciadas en los JSONs de configuración (landing y campañas) y en la BD (productos, categorías), identificando y limpiando huérfanas con tres capas de seguridad: grace period de 14 días, modo dry-run por defecto, y soft-delete a un prefijo {{_trash/}} con retención de 30 días.

h2. User Stories

1. Como administrador de Quenova, quiero que cuando reemplace una imagen de un producto en el backoffice, la imagen anterior se borre automáticamente de S3, para que el bucket no acumule archivos innecesarios.
2. Como administrador de Quenova, quiero que cuando modifique el contenido visual de la landing page (banners, logos, imágenes de secciones), las imágenes anteriores sean limpiadas periódicamente, para mantener los costos de S3 controlados.
3. Como administrador de Quenova, quiero que cuando configure una nueva campaña y reemplace banners o imágenes de secciones, las imágenes previas de esa campaña sean identificadas como huérfanas y limpiadas, para evitar acumulación.
4. Como administrador de Quenova, quiero que las imágenes no se borren definitivamente de inmediato, sino que se muevan a una "papelera" ({{_trash/}}) durante 30 días, para poder recuperarlas si se cometió un error.
5. Como administrador de Quenova, quiero que el sistema de limpieza tenga un modo "dry run" que logee lo que borraría sin borrar nada, para poder validar el comportamiento antes de activar el borrado real.
6. Como administrador de Quenova, quiero que las imágenes subidas recientemente (menos de 14 días) nunca sean candidatas a borrado automático, para proteger contra race conditions entre la subida y la actualización del JSON/BD.
7. Como administrador de Quenova, quiero que la frecuencia del sweep sea configurable, para poder ajustarla según las necesidades operativas sin cambiar código.
8. Como administrador de Quenova, quiero que cuando borre una imagen de un producto desde el backoffice, si el borrado en S3 falla, la operación del usuario no se bloquee y el sweep semanal la recoja después.
9. Como administrador de Quenova, quiero que cuando se borre una imagen de una categoría (header o carousel) o de un usuario (avatar), estas también se limpien de S3 de forma automática.
10. Como administrador de Quenova, quiero poder ver en los logs de CloudWatch un resumen claro de cada ejecución del sweep: cuántos objetos escaneó, cuántos identificó como huérfanos, cuántos movió a trash, para tener visibilidad operativa.
11. Como administrador de Quenova, quiero que las configuraciones de campañas pasadas en el array {{visualConfig[]}} del JSON de configuración no impidan la limpieza, es decir, que solo las URLs de la campaña activa y el default se consideren como referenciadas.
12. Como ingeniero de Quenova, quiero que el borrado de imágenes de producto use los domain events existentes ({{ProductImageDeletedEvent}}), para mantener la consistencia con la arquitectura DDD del backend.

h2. Implementation Decisions

h3. Arquitectura de dos capas

* *Eager Delete* (Capa 1): Event handlers fire-and-forget en la capa de infraestructura del backend NestJS que escuchan los domain events de borrado de imagen y ejecutan {{DeleteObjectCommand}} contra S3. Si falla, se logea como warning — la operación del usuario no se interrumpe.
* *Weekly Sweep* (Capa 2): Handler adicional en el repositorio {{image-sync-lambda}}, triggered por EventBridge schedule rule, que construye un registro de imágenes referenciadas cruzando S3 config JSONs y la API del backend, y mueve las huérfanas a {{_trash/}}.

h3. Ubicación del sweep: co-localización en image-sync-lambda

El cleanup handler vive en el mismo repositorio que la Image Sync Lambda existente, como un segundo handler exportado ({{cleanupHandler}}) con su propio trigger EventBridge. Razones: reutiliza infra de S3 y la API_KEY de autenticación al backend, Lambda elimina duplicados de ejecución, y evita crear un repo/pipeline nuevo. Decisión documentada en ADR-0006.

h3. Extensión del IStorageService

El puerto {{IStorageService}} del backend solo expone {{downloadFile}} y {{checkIfUrlIsValid}}. Se debe agregar {{deleteFile(fileUrl: string): Promise<void>}} e implementarlo en {{S3Service}} con {{DeleteObjectCommand}}.

h3. Scope de prefijos monitoreados por el sweep

|| Grupo || Prefijos || Fuente de verdad ||
| Content Manager Landing | {{header/}}, {{home/}}, {{aboutus/}}, {{joinus/}}, {{footer/}}, {{contact/}}, {{award/}}, {{categories/}}, {{digital-magazine/}} | {{landing/config.json}} en S3 |
| Content Manager Campañas | {{campaigns/\{id\}/...}} | {{ecommerce/config.json}} en S3 |
| Productos | {{products/\{id\}/...}} | PostgreSQL ({{imageUrls}} array), consultado vía {{GET /products}} API |
| Categorías | {{categories/...}} | PostgreSQL ({{headerImageUrl}}, {{carouselImagesUrls}}), consultado vía {{GET /categories}} API |
| Usuarios | {{users/...}} | PostgreSQL, consultado vía API del backend |

h3. Tres capas de seguridad

* *Grace Period* ({{GRACE_PERIOD_DAYS=14}}): Solo considerar como candidatas imágenes con {{LastModified}} > 14 días.
* *Dry Run* ({{DRY_RUN=true}}, default): Logear sin borrar. Requiere flip explícito para activar borrado.
* *Soft Delete*: Mover a {{_trash/\{original-key\}}} via {{CopyObject + DeleteObject}}. S3 Lifecycle Rule borra permanentemente a los 30 días.

h3. Consulta de imágenes de producto para el sweep

El sweep usa los endpoints existentes {{GET /products}} (paginado, iterando todas las páginas) y {{GET /categories}} para obtener las URLs referenciadas. No se crea un endpoint nuevo — la ineficiencia del payload completo es irrelevante para un batch semanal.

h3. Configuración del sweep via env vars

* {{DRY_RUN}}: {{true}} (default) | {{false}}
* {{GRACE_PERIOD_DAYS}}: {{14}} (default)
* {{CLEANUP_SCHEDULE_EXPRESSION}}: {{rate(7 days)}} (default)
* {{LANDING_CONFIG_BUCKET}}, {{LANDING_CONFIG_PATH}}, {{ECOMMERCE_CONFIG_PATH}}, {{IMAGES_BUCKET}}, {{TRASH_PREFIX}}

h3. Cambios en Terraform

* S3 Lifecycle Rule: {{aws_s3_bucket_lifecycle_configuration}} para el {{imagesBucket}} con expiración de 30 días en prefijo {{_trash/}}.
* EventBridge Schedule Rule configurable para el cleanup handler.
* IAM: agregar {{s3:ListBucket}}, {{s3:CopyObject}}, {{s3:DeleteObject}} al role de la Lambda.

h2. Testing Decisions

Good tests verify external behavior, not implementation details. Los tests deben confirmar: "dado este estado del bucket y estas referencias, ¿se identificaron correctamente las huérfanas?"

h3. Módulos con tests

* *CleanupHandler (Lambda)*: Tests unitarios con mocks de S3 y de la API del backend. Verificar: identificación correcta de huérfanas, respeto del grace period, comportamiento de dry-run vs. ejecución real, manejo de errores.
* *Config Parser (Lambda)*: Tests unitarios que parsean JSONs de configuración de landing y campañas y extraen correctamente todas las URLs de imagen referenciadas.
* *Product Image Cleanup Event Handler (Backend)*: Test que verifica que al emitir {{ProductImageDeletedEvent}} se invoca {{IStorageService.deleteFile}} con la URL correcta, y que si falla, no lanza excepción.
* *S3Service.deleteFile (Backend)*: Test unitario con mock de S3Client que verifica la invocación correcta de {{DeleteObjectCommand}}.

h3. Prior art

* Los tests existentes en {{image-sync-lambda/test/}} para la lógica de sync.
* Los tests unitarios del módulo Product en el backend para domain events.

h2. Out of Scope

* *Borrado desde el backoffice Angular*: No se descomentarán ni habilitarán las funciones {{deleteImage}} en los servicios del backoffice. El borrado se centraliza en el backend (eager) y la Lambda (sweep).
* *Limpieza del array {{visualConfig[]}} en los JSONs*: Las configuraciones de campañas pasadas se acumulan en el JSON pero no se limpian en este requerimiento. Solo se usan como fuente de referencia para el sweep.
* *Métricas CloudWatch custom o notificaciones Slack*: Se limita a CloudWatch Logs (Nivel 1). Alertas adicionales se implementarían en un requerimiento futuro si es necesario.
* *Migración del content manager al backend*: El content manager sigue operando directamente contra S3 desde Angular. No se centraliza la gestión de imágenes del content manager a través del backend en este requerimiento.
* *Renombramiento del repo image-sync-lambda*: Aunque se recomienda actualizar el README del repo, el renombramiento formal del repositorio queda fuera de scope.

h2. Further Notes

* El ADR-0006 documenta la decisión de co-localizar el cleanup handler en el repo {{image-sync-lambda}}.
* La prioridad de implementación del eager delete es: Productos → Categorías → Usuarios.
* El sweep debe ejecutarse por primera vez en modo {{DRY_RUN=true}} en staging y producción antes de activar el borrado real, para validar que no se identifiquen falsos positivos.
* El {{GRACE_PERIOD_DAYS}} de 14 días combinado con los 30 días de retención en {{_trash/}} da un margen total de 44 días desde que una imagen se sube hasta que podría ser permanentemente borrada.
