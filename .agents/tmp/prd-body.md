## Declaración del Problema

Actualmente, los productos pertenecientes a Líneas o Sublíneas desactivadas siguen siendo visibles en el ecommerce y pueden ser incluidos en nuevas Cotizaciones (Quotes). No existe una regla de negocio que impida la venta de productos cuya Línea o Sublínea ha sido desactivada por un administrador. Esto permite que se creen transacciones comerciales con productos que Quenova no desea vender.

## Solución

Implementar una regla de negocio compuesta llamada **Disponible para la Venta (Available for Sale)**: un Producto está disponible para la venta cuando se cumplen tres condiciones simultáneamente: el Producto está activo, su Línea está activa y su Sublínea está activa.

Esta regla se aplica en dos puntos:
1. **Consultas de productos**: Todas las consultas de productos incluirán un campo computado `availableForSale` en la respuesta. No se filtran productos por defecto — el filtro es opt-in para que el ecommerce lo active explícitamente y el backoffice vea todo.
2. **Creación de Cotizaciones**: Se rechaza la creación de una Cotización si alguno de sus productos no está disponible para la venta. El rechazo es total (falla toda la Cotización) y reporta en batch qué productos específicos no están disponibles.

## Historias de Usuario

1. Como administrador del backoffice, quiero ver todos los productos con un indicador visual de si están disponibles para la venta, para poder gestionar qué líneas/sublíneas están activas.
2. Como administrador del backoffice, quiero desactivar una Línea y que automáticamente todos sus productos se marquen como no disponibles para la venta, para controlar qué productos se venden en el ecommerce.
3. Como administrador del backoffice, quiero desactivar una Sublínea específica dentro de una Línea activa, para tener control granular sobre qué subdivisiones de productos están disponibles.
4. Como administrador del backoffice, quiero reactivar una Línea o Sublínea previamente desactivada y que sus productos vuelvan a estar disponibles para la venta inmediatamente.
5. Como cliente del ecommerce, quiero que al buscar productos con el filtro `availableForSale=true`, solo vea productos que puedo comprar, para no intentar comprar algo no disponible.
6. Como cliente del ecommerce, quiero que si intento crear una Cotización con un producto no disponible, reciba un error claro indicando exactamente qué productos no están disponibles, para poder corregir mi pedido.
7. Como micronova, quiero que si intento crear una Cotización para un cliente con productos de líneas desactivadas, reciba un error descriptivo con los IDs de los productos no disponibles, para informar al cliente.
8. Como cliente con una Cotización existente cuya Línea fue desactivada después de su creación, quiero que mi Cotización siga siendo válida y pueda completar mis pagos, porque el compromiso comercial ya fue establecido.
9. Como administrador del backoffice, quiero que el endpoint GET /products/:id devuelva el producto con el campo `availableForSale` incluso si es `false`, para poder inspeccionar productos individuales de líneas desactivadas.
10. Como administrador del backoffice, quiero que la exportación de productos incluya el campo de disponibilidad, para generar reportes completos del catálogo.
11. Como desarrollador frontend del ecommerce, quiero poder filtrar productos por `availableForSale` en el endpoint POST /products/search, para mostrar solo productos comprables sin duplicar lógica de negocio.
12. Como desarrollador frontend del backoffice, quiero recibir el campo `availableForSale` en todas las respuestas de productos sin necesidad de enviar filtros adicionales, para mostrar indicadores visuales.

## Decisiones de Implementación

- **Regla canónica en el dominio**: La regla `isAvailableForSale` vive como getter en la entidad de dominio `Product`, compuesta por: `status === ACTIVE && line.isActive && subline.isActive`. Ver ADR-0004.
- **Infraestructura espeja la regla**: Para consultas con paginación, el repositorio distribuido aplica el filtro equivalente a nivel de datos (infra mirror). Actualmente el filtrado es in-memory sobre entidades de dominio hidratadas, por lo que el getter se invoca directamente sin duplicación real.
- **Campo computado en el modelo de lectura**: `ProductModel` (read model) incluirá un campo `availableForSale: boolean`, computado por `ProductMapper.toModel()` invocando el getter del dominio.
- **Filtro opt-in en SearchProductsFilters**: Se añade `availableForSale?: boolean` como filtro opcional en `SearchProductsFilters`. Los filtros `status` y `availableForSale` son independientes (AND), sin interacción especial.
- **Validación en PricingService (módulo Sales)**: `PricingService.calculatePrice()` verifica `product.isAvailableForSale` como precondición antes de calcular precios. Si el producto no está disponible, lanza error. Ver advertencias documentadas en ADR-0004 sobre acoplamiento de módulos y SRP.
- **Error como invariante de Sales**: El error `ProductsNotAvailableForSaleError` se define en `sales/domain/errors/`, no en el módulo Product. Es un invariante de ventas ("no se puede vender lo que no está disponible"), no una propiedad del producto. Se reportan en batch todos los productos no disponibles.
- **Rechazo total en creación de Cotización**: Si cualquier producto en la Cotización no está disponible, se rechaza la Cotización completa (hard reject). El error incluye los IDs de todos los productos no disponibles.
- **Política no retroactiva**: Las Cotizaciones existentes no se ven afectadas por la desactivación posterior de Líneas/Sublíneas. Los pagos sobre Cotizaciones existentes siguen funcionando normalmente.
- **Documentación actualizada**: CONTEXT.md actualizado con los términos "Available for Sale", activación de Línea y Sublínea. ADR-0004 creado documentando la estrategia "domain defines, infra mirrors".

## Decisiones de Testing

- Los tests deben verificar comportamiento externo, no detalles de implementación.
- **Entidad Product**: Tests unitarios para el getter `isAvailableForSale` cubriendo todas las combinaciones de estados (producto activo/inactivo × línea activa/inactiva × sublínea activa/inactiva). Ya existen tests de Product en `test/unit/modules/product/`.
- **PricingService**: Tests unitarios verificando que lanza error para productos no disponibles y que calcula precios normalmente para productos disponibles.
- **Filtro de búsqueda**: Tests verificando que `applySearchFilters` filtra correctamente cuando se pasa `availableForSale=true`.
- **ProductMapper.toModel**: Test verificando que el campo `availableForSale` se mapea correctamente desde el getter del dominio.

## Fuera de Alcance

- Desactivación de Categorías y su efecto en disponibilidad de productos.
- Cancelación retroactiva automática de Cotizaciones existentes al desactivar una Línea.
- Interfaz de usuario del backoffice o ecommerce (solo el contrato de API).
- Migración a un Read Model materializado en Postgres.
- Notificaciones a Micronovas cuando una Línea se desactiva.
- Extracción de un `IProductAvailabilityPort` dedicado (documentado como evolución futura en ADR-0004).

## Notas Adicionales

- Esta funcionalidad se construye sobre las entidades de dominio Line y Subline con `isActive` que fueron introducidas en QUEN-2416/2417.
- El endpoint PATCH /lines/:id ya permite activar/desactivar líneas y sublíneas. No se requieren cambios en ese endpoint.
- El campo `availableForSale` es derivado y nunca se persiste — siempre se computa desde los estados actuales del producto, línea y sublínea.
