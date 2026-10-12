# Hoja de ruta de 0 a 1.0

Estado: ✅ hecho · 🟡 parcial · ⬜ pendiente. Actualizado el 12-10-2026.

## Fase 0 — Prototipo técnico ✅
- ✅ Proyecto Godot 4.7 con `sim/` separada (ADR-001).
- ✅ Modos ventana y franja, transparencia, click-through y siempre encima (ADR-004).
- ✅ MultiMesh de hormigas con atlas e interpolación.
- ✅ Bajo consumo sin foco (10 FPS, pasos de 0,5 s).
- 🟡 Click-through verificado en Windows y X11; Wayland y macOS sin probar.
- ⬜ CI (GitHub Actions con Godot headless).

## Fase 1 — Prototipo de simulación ✅
- ✅ Suelo con materiales, excavación y partículas de tierra suelta.
- ✅ Feromonas con evaporación perezosa y capa visual.
- ✅ Forrajeo con reclutamiento por rastro.
- ✅ Umbrales de respuesta con refuerzo y estímulo dinámico.
- ✅ Determinismo (`state_hash`) y conservación del suelo.
- ✅ Ocupación de nodos (sin apelotonamiento).

## Fase 2 — Vertical slice con *Messor barbarus* 🟡 (en curso)
- ✅ Fundación claustral completa (excavar, sellar, lote, nanitics, reabrir).
- ✅ Castas (menor, media, mayor) por tamaño de colonia; molienda; granero; basurero.
- ✅ Calendario real, fotoperiodo, diapausa, formicario doméstico (ADR-003).
- ✅ Diario, ayuda, «mientras no estabas», lupa.
- ✅ Guardado atómico con copias; progreso offline analítico coherente con el online.
- ⬜ Pistas contextuales del tutorial en el cuaderno.
- ⬜ Marca de excavación (sugerir dónde ampliar).
- ⬜ Exportación para Windows (`export_presets.cfg`) y prueba de 8 horas con testers.
- **Criterios de aceptación:** primera obrera en 40–55 h reales en modo acompañante ✅ (~día 40 ≈ 40 h); offline a menos de ±15 % del online ✅ (test); cargar una partida de la versión anterior ⬜ (hay `migrate()`, falta un fixture); 8 h abierto sin cierres ni consumo anómalo ⬜.

## Fase 3 — Alpha ⬜
1. **Vuelo nupcial y prestigio:** sexuados en colonias maduras; disparador de septiembre u octubre tras lluvia (lluvia simulada en el calendario); linajes Mbar1/Mbar2 con espermateca; rasgos heredados; álbum de colonias.
2. **LOD de población** por encima de 1.200 agentes: agentes que representan grupos; el recuento real sigue en `Colony`.
3. **Eventos:** depredador en el outworld (araña), cadáveres y patógenos, sobrecalentamiento.
4. **Marca de excavación**, humidificar por zona.
5. **Bandeja del sistema** (`StatusIndicator`), notificaciones discretas, «no molestar».
6. **Localización** es/en con `tr()` y `.po`; accesibilidad (escala de UI, reducir movimiento).
7. **Audio** ambiente con buses.
8. Iconos pixel en la barra y fuente pixel.
- **Criterios:** 15.000 obreras reales con menos del 10 % de CPU con foco; ciclo fundación → vuelo en 25–40 días reales en modo acompañante; todos los textos traducidos.

## Fase 4 — Beta y demo ⬜
- *Polyergus rufescens* jugable: fundación por usurpación, exploradoras, incursiones a última hora de la tarde, esclavas *Formica*. La proporción de incursiones fallidas debe emerger entre el 20 y el 40 % (referencia: ~29 %).
- Hormiga argentina como evento (límites térmicos).
- Modo campo opcional (lluvia, inundación, colonias vecinas).
- Steamworks (logros, nube); demo para el Next Fest; telemetría opcional.
- Página de Steam publicada al menos 3 meses antes de la 1.0.

## Fase 5 — 1.0 ⬜
Pulido, rendimiento y guardados, cuaderno de campo completo, créditos científicos dentro del juego, *trailer*, lanzamiento junto a un festival.

## Después de la 1.0
*Aphaenogaster senilis* (fisión), *Lasius niger* (pulgones), *Pheidole pallidula* jugable, *Formica sanguinea*; Steam Workshop; formicarios conectados por tubos; más idiomas; hongos y mirmecófilos.

## Riesgos
| Riesgo | Mitigación |
|---|---|
| Rendimiento de GDScript con muchos agentes | SoA, tope de agentes, LOD; GDExtension como plan B |
| Click-through inconsistente (Wayland, macOS) | Modo ventana como alternativa; documentarlo en la tienda |
| El realismo aburre | Modo acompañante por defecto, diario, lupa, cuaderno de descubrimientos |
| Datos de criadores poco fiables | Etiquetas [C]/[A]/[D], parámetros en JSON, revisión por un mirmecólogo |
| Guardados rotos tras actualizar | Escritura atómica, copias, migraciones con fixtures |
