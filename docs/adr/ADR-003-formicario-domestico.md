# ADR-003 — Fantasía de juego: el formicario doméstico

- **Estado:** aceptada
- **Fecha:** 2026-10-12

## Contexto

El GDD de la investigación planteaba un corte de campo ibérico con clima exterior, lluvia, vecinos y depredadores. Para el vertical slice hace falta una fantasía más acotada y que se entienda a la primera, y que además encaje con lo que hacen de verdad los aficionados a la cría de hormigas.

## Decisión

El jugador es el **cuidador de un formicario de cristal** que tiene en casa (en España). Lo que se ve es un formicario de sustrato natural con una zona de forrajeo (outworld) arriba. Las herramientas son las de un criador real:

| Herramienta | Efecto en la simulación |
|---|---|
| Comedero de semillas | `env.feeder_seeds`; las forrajeras lo vacían y llenan el granero |
| Tubo de agua con algodón | `env.water_ml` rehidrata el sustrato hacia `target_humidity` |
| Manta térmica | +3 °C al nido (`heater_on`); acelera el desarrollo hasta la meseta de 26–30 °C |
| Hibernación automática | Del 1 de diciembre al 31 de enero, el nido a 14 °C (diapausa) |
| Prioridad y pincel de feromona | Influencia, nunca control directo (ver GDD) |

El clima es el de **una casa española sin climatizar**: unos 19 °C en invierno, unos 26 °C en verano y ±1 °C entre el día y la noche (`FormicariumEnv.room_temp`). El fotoperiodo corresponde a unos 40° N.

## Consecuencias

- La fantasía es verosímil y educativa: el juego enseña a criar *Messor barbarus* de verdad.
- Lluvia, frentes meteorológicos, vecinos y depredadores quedan para fases posteriores, como un modo «campo» o como eventos en el outworld. El **vuelo nupcial** (fase alpha) sí encaja en el formicario: los alados salen al outworld y el jugador decide cuándo abrir la tapa, siguiendo los disparadores reales (septiembre y octubre, tras lluvia).
- Los mechones de hierba del sustrato naturalista dan semillas estacionales (mayo y junio), así que hay algo de forrajeo aunque el jugador olvide el comedero.
