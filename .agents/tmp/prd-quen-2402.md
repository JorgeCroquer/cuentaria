## Declaración del Problema

Actualmente, las franquicias (Micronovas y Supernovas) no tienen una herramienta para proyectar sus ganancias antes de procesar una orden. Para estimar cuánto ganarán con una venta, deben realizar cálculos manuales usando los porcentajes de comisión por línea de producto, los descuentos de campaña activa y las reglas de Revenue Share — información dispersa entre Profit y el backend. Esto dificulta la planificación comercial y genera incertidumbre sobre la rentabilidad de cada pedido.

## Solución

Un **Simulador de Ganancias** integrado en el backoffice de franquicias que permite:

1. **Simular un pedido virtual** — El usuario arma un carrito de productos con cantidades y visualiza en tiempo real el desglose financiero completo: precio base, descuentos de campaña, total a pagar por el cliente, y su ganancia estimada (Micronova Share o Supernova Share según el rol).

2. **Cargar una orden existente** — El usuario selecciona una Quote ya procesada y visualiza el desglose financiero real tal como fue calculado al momento de la creación de la orden.

El sistema recalcula automáticamente cada vez que se agrega, modifica o elimina un producto del carrito simulado.

## Historias de Usuario

1. Como **Micronova**, quiero simular un pedido agregando productos y cantidades, para proyectar cuánto ganaré antes de ofrecer productos a mis clientes.
2. Como **Micronova**, quiero ver el desglose por producto de mi ganancia (porcentaje y monto), para entender qué productos me generan más rentabilidad.
3. Como **Micronova**, quiero ver el total de descuentos de campaña aplicados, para saber cuánto pagará realmente mi cliente.
4. Como **Micronova**, quiero cargar una Quote existente en el simulador, para visualizar el desglose financiero de una orden que ya procesé.
5. Como **Supernova**, quiero simular un pedido y ver mi ganancia estimada como Supernova (mi porcentaje sobre la venta neta), para proyectar mis ingresos por la actividad de mi red.
6. Como **Supernova**, quiero alternar entre la vista de Micronova y Supernova en el simulador, para comparar la ganancia desde ambas perspectivas (ya que soy ambas simultáneamente).
7. Como **Supernova**, quiero ver un bloque de "Cálculo de Base Neta" que muestre transparentemente cómo se deducen el margen de la Micronova y el IVA de mi ganancia, para entender de dónde sale mi dinero.
8. Como **Supernova**, quiero cargar Quotes de cualquier Micronova de mi red en el simulador, para analizar la rentabilidad de las ventas de mis Micronovas.
9. Como **Micronova pura** (sin rol de Supernova), no debo ver el toggle de rol ni la vista de Supernova, para mantener la interfaz simple y relevante.
10. Como **usuario administrador de Quenova**, quiero acceder al simulador, para poder dar soporte y responder consultas de las franquicias sobre sus ganancias.
11. Como **usuario del simulador**, quiero que los productos no disponibles para la venta no aparezcan en el catálogo del simulador, para simular solo con productos que realmente puedo vender.
12. Como **usuario del simulador**, quiero que el recalculo sea rápido (menos de 300ms) cuando agrego o cambio productos, para que la experiencia sea fluida.
13. Como **usuario del simulador**, quiero ver un aviso de que los montos son estimados y pueden variar en centavos al procesar la orden real, para tener expectativas correctas.
14. Como **Micronova**, quiero que al cargar una orden existente se muestren los datos financieros reales de esa orden (no recalculados con la campaña actual), para ver exactamente cuánto gané en esa venta.

## Decisiones de Implementación

### Arquitectura General

- El simulador es una **proyección de solo lectura** del cálculo de pricing existente. No introduce nuevos conceptos de dominio, agregados ni entidades. La "simulación" es una etiqueta de UI, no un término de dominio.
- Vive **dentro del módulo de `sales`** como un nuevo servicio de aplicación (`SimulatorService`) y un endpoint de consulta. No se crea un módulo nuevo.

### Endpoint Principal: `POST /simulator/calculate`

- Recibe un array de `{ productId, quantity }` representando el carrito completo.
- Retorna el `PriceDetails` por producto (con `RevenueShare` completo: micronovaShare, supernovaShare, quenovaShare) y los totales agregados.
- El endpoint es **agnóstico al rol** — siempre retorna las tres partes del Revenue Share. El frontend decide cuál mostrar según el tipo de franquicia del usuario logueado.
- Usa `throwOnUnavailable: true` como red de seguridad — si un producto se desactiva entre la carga del dropdown y la llamada de cálculo, retorna un error claro.

### Optimización: Campaign Caching

- El `SimulatorService` cachea la Campaña activa (con sus Discounts y Line Commissions) con un TTL corto (~5 minutos). Esto elimina la llamada a Profit en cada cálculo.
- El primer request calienta la caché (~300ms). Los subsiguientes son ~50ms (solo fetch de productos + cálculo puro).
- La caché es **local al SimulatorService** — no afecta al `PricingService` usado para la creación real de Quotes, el cual siempre consulta datos frescos.
- La implementación de una caché más amplia para la Campaña a nivel de plataforma (ecommerce, catálogo) queda fuera de alcance de este issue y se manejará como un issue separado.

### "Cargar Orden Existente"

- Utiliza los queries existentes: `GetUserQuotesQuery` para listar las Quotes en el dropdown y `GetQuoteByIdQuery` para cargar los datos completos.
- Muestra los **datos persistidos** de la Quote (Revenue Share, descuentos, totales calculados al momento de la creación). No recalcula con la campaña actual.
- Para Micronovas: muestra sus propias Quotes. Para Supernovas: muestra las Quotes de todas las Micronovas de su red (ya soportado por `GetUserQuotesHandler` via filtro `parentIds`).

### Vista de Supernova (IVA y Base Neta)

- El bloque "Cálculo de Base Neta de Red" es una **preocupación exclusiva del frontend**. El backend retorna el `supernovaShare` como un monto correcto en dólares. El frontend hace la derivación inversa usando la constante de IVA (16%) para mostrar la "Venta Neta Real" y las deducciones de forma transparente.
- Este cálculo es puramente presentacional — matemáticamente equivalente al resultado del backend, solo expresado de forma diferente para la comprensión de la Supernova.

### Permisos

- Accesible para usuarios de tipo Franchise (Micronova y Supernova) y Quenova (administradores).
- No se crea un permiso dedicado en esta iteración, pero el endpoint se estructura con un guard genérico que facilite agregar un permiso específico en el futuro.

### Decisión Arquitectónica Registrada

- **ADR-0005**: Se registró la decisión de mantener toda la lógica de cálculo en el backend vía un endpoint batch, en lugar de precargar reglas de negocio al frontend. Se evaluaron 4 alternativas (frontend completo, debounced, preload de contexto, batch on-demand) y se eligió batch por: cero leak de lógica de negocio, precisión exacta de redondeo, soporte transparente de tiers de descuento, y latencia aceptable (~50ms por request tras calentamiento de caché).

## Decisiones de Testing

### Criterio de un buen test

Un buen test verifica el **comportamiento externo** del módulo — los inputs y outputs de su interfaz pública — sin acoplarse a detalles de implementación internos. Si un refactor cambia la implementación pero no el comportamiento, el test no debe romperse.

### Módulos a testear

1. **SimulatorService** — Tests unitarios verificando:
   - Cálculo correcto del Revenue Share para un carrito con múltiples productos de distintas líneas
   - Aplicación correcta de descuentos de campaña (incluyendo tiers por cantidad cuando aplique)
   - Comportamiento con caché caliente vs fría
   - Manejo de productos no disponibles para la venta
   - Carrito vacío (edge case)

2. **Endpoint `POST /simulator/calculate`** — Tests de integración verificando:
   - Respuesta correcta con carrito válido
   - Error 400 con productos inexistentes
   - Error cuando un producto no está disponible para la venta
   - Estructura de respuesta completa (todos los campos del PriceDetails + RevenueShare)

### Referencia de tests existentes

- Tests unitarios del dominio: `quote.entity.spec.ts` como patrón para tests de lógica de negocio
- Tests del `PricingService` existente como referencia para mocking de `ICampaignRepository` e `IProductRepository`

## Fuera de Alcance

- **Caché de Campaña a nivel de plataforma** — La optimización de caché para el ecommerce y catálogo general se manejará como un issue separado. En este issue solo se implementa la caché local al SimulatorService.
- **Permiso dedicado del simulador** — El sistema de permisos está en desarrollo. Se estructura para facilitar la adición futura pero no se crea un permiso específico ahora.
- **Frontend del simulador** — Este PRD cubre exclusivamente la implementación del backend. La implementación del frontend (UI, toggle de roles, bloque de Supernova) se manejará como un issue independiente o subtarea.
- **Macronovas** — El nivel intermedio futuro entre Supernova y Micronova no se contempla en esta iteración, pero la arquitectura del `RevenueShare` (que ya retorna las tres partes por separado) es extensible naturalmente.
- **Reporte de simulaciones** — No se persisten ni auditan las simulaciones. Son efímeras.
- **Conversión de moneda VES** — El simulador opera exclusivamente en USD (Base Currency). No se incluye conversión a bolívares en esta iteración.

## Notas Adicionales

### Glosario Estricto

- Está **prohibido** usar la palabra "Comisión" en la interfaz. El término oficial es "Ganancia" o "Ganancia Estimada".
- Los términos del dominio (Quote, Revenue Share, Line Commission, etc.) se definen en `CONTEXT.md` del repositorio.

### Prototipo de Referencia

- El archivo `Quenova_Simulador_Ganancias_MOBILE.html` contiene un prototipo funcional que ilustra la UX deseada. **Importante**: el prototipo calcula todo en el frontend con constantes hardcodeadas — esta NO es la arquitectura correcta. El backend es la autoridad de cálculo.

---

## Descripción Original del Issue

> Este módulo permitirá a nuestra red proyectar sus ingresos armando pedidos virtuales o extrayendo órdenes existentes. **(APLICA PARA MICRONOVA Y SUPERNOVA)**
>
> Para facilitar la integración, dentro de la misma maqueta incluí una pestaña llamada "Guía Devs (Lógica)" con la documentación técnica. Los puntos más críticos a considerar para el Backend y el Frontend son:
>
> **Lógica Matemática Dinámica:** El cálculo de la ganancia no es plano. Varía dependiendo del Rol (Micronova vs. Supernova) y de la Línea de Producto (Cuidado Bucal, Cuidado Personal, Joyería, etc.). En la guía dejé la tabla exacta de multiplicadores a usar.
>
> **UI Adaptativa por Rol:** Si el usuario logueado es una Supernova, la interfaz debe inyectar un bloque especial ("Cálculo de Base Neta") para transparentar las deducciones de IVA y margen base.
>
> **Glosario Estricto:** Por regla de negocio, está prohibido usar la palabra "Comisión" en la interfaz. El término oficial a programar es siempre "Ganancia" o "Ganancia Estimada".
>
> **Modos de Uso:** El módulo maneja dos estados visuales ("Simular Nuevo Pedido" y "Cargar Orden Existente").
>
> Revisar la maqueta y la guía técnica.
