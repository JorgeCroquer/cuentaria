---
description: Generador de Mensajes de Commit
---

## Instrucciones:

1. Ejecuta el comando `git diff --cached` para analizar únicamente los cambios preparados (staged).
2. Genera un título de commit conciso siguiendo el estándar de Conventional Commits (feat, fix, refactor, chore, etc.). Seguido entre parentesis del feature o module que se esta agregando modificando. Si es un breaking change debe ser asi feat(module)!:
3. Usa el tiempo verbal imperativo (ej. "Añade validación" en lugar de "Añadida validación").
4. Escribe el mensaje completamente en ingles y con menos de 100 caracteres para el titulo y menos de 100 para el body. Si necesitas mas usa enter para una nueva linea.
5. Si hay cambios complejos, agrega una breve lista de viñetas en la descripción (el "body" del commit).

## Restricciones:

- No termines el título del commit con un punto.
- Proporciona solo el texto del commit listo para copiar y pegar, o propón el comando `git commit -m` completo.
