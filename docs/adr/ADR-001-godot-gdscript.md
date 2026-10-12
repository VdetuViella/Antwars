# ADR-001 — Godot 4.7 con GDScript (sin .NET)

- **Estado:** aceptada
- **Fecha:** 2026-10-12

## Contexto

La investigación inicial (ver `docs/ARQUITECTURA.md`) recomendaba Godot 4 con el núcleo de simulación en C#, porque C# da más rendimiento en bucles calientes y permite probar la simulación con `dotnet test` sin abrir el motor.

En el entorno de desarrollo (contenedor Linux en la nube donde trabaja el agente) no hay SDK de .NET. Desde la red permitida solo se puede descargar el binario estándar de Godot (GitHub Releases). La versión .NET de Godot exige el SDK para compilar y exportar.

## Decisión

- Se usa **Godot 4.7.x estándar** (binario oficial, sin .NET) y **GDScript con tipado estático** en todo el proyecto.
- La separación que pedía la recomendación original se mantiene **por convención**: todo lo que hay en `sim/` son clases `RefCounted` sin nodos, escenas, señales ni reloj del sistema, y `game/` solo presenta y envía órdenes.
- Los tests se ejecutan headless con el propio Godot (`tests/run_tests.gd`), sin depender de un framework externo.

## Consecuencias

- **Rendimiento:** GDScript es más lento que C#. Para compensarlo, los agentes se guardan como estructuras de arrays (`Packed*Array`), las feromonas se evaporan de forma perezosa, la navegación usa campos BFS precalculados, el suelo solo actualiza las celdas activas y se fija un tope de agentes visibles con LOD de población. Medido: unos 0,3 ms por tick con unas 10 hormigas y unos 1–2 ms con 120.
- **Riesgo:** si a partir de unas 2.000 hormigas visibles el coste por tick supera el presupuesto (unos 4 ms), el plan B es portar `sim/ants.gd` y `sim/nav_grid.gd` a una GDExtension en C++ o Rust, sin tocar la interfaz de `SimWorld`.
- **Ventaja:** el proyecto es texto plano (`.gd`, `.tscn`, `.json`), cómodo para un agente, y se abre en cualquier instalación estándar de Godot 4.7.
