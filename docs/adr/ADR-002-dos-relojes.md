# ADR-002 — Dos relojes: comportamiento y biología

- **Estado:** aceptada
- **Fecha:** 2026-10-12

## Contexto

Una colonia real tarda unas 6–7 semanas en producir su primera obrera y años en madurar. Si todo el juego corriera a ×1 sería aburrido. Si todo corriera a ×24, las hormigas se moverían a 24 veces su velocidad y no se podrían mirar, que es el sentido de un compañero de escritorio.

## Decisión

La simulación tiene dos relojes independientes (`SimWorld.advance`):

1. **Reloj de comportamiento.** Las hormigas visibles se mueven a velocidad real (unos 14 px/s, es decir, unos 14 mm/s; paso fijo de 0,1 s). Es lo que se ve en pantalla.
2. **Reloj biológico.** El calendario, la puesta, el desarrollo de la cría, el consumo, la humedad y la mortalidad avanzan a la escala elegida (`time_scale`: realista ×1, acompañante ×24, acelerado ×96), con un paso fijo de 10 minutos biológicos.

Para que la economía cuadre en cualquier escala, **cada segundo de trabajo visible representa `work_value() = time_scale / behaviour_speed` segundos de trabajo biológico**. Una semilla visible que lleva una forrajera equivale a `work_value()` semillas reales: a ×24, un viaje visible representa los viajes que esa obrera haría en 24 veces más tiempo.

## Consecuencias

- El modelo de colonia (`Colony.step`) es el mismo con el juego abierto y en el progreso offline (`OfflineResolver`), así que ambos son coherentes por construcción (comprobado en `test_offline_matches_online_population`).
- La excavación visible es trabajo físico real de los agentes y **no** se escala con `work_value()`. A escalas muy altas (las de los tests, ×400 o ×800) el nido va por detrás de la biología. En el juego normal (×24) va por delante. El generador de partidas de prueba compensa esto con la excavación rápida offline.
- Las escalas por encima de ×96 solo existen para depurar (tecla F9) y para los tests.
