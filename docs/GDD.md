# AntWars — Documento de diseño del juego (GDD)

> Versión 0.2 · 12-10-2026 · Estado de cada mecánica: ✅ implementada · 🟡 parcial · ⬜ pendiente

## 1. Visión

**AntWars** es un formicario de cristal que vive en tu escritorio. Dentro hay una colonia de *Messor barbarus*, la hormiga granívora más común de la Península Ibérica. Lo que ves no está guionizado: cada obrera decide sola a partir de lo que huele y lo que necesita la colonia, y el nido que excavan es único. Tú eres el **cuidador** (ADR-003): rellenas el comedero y el agua, controlas el calor y empujas a la colonia con prioridades y feromonas. Puedes dejarlo funcionando todo el día y mirarlo de vez en cuando, como un acuario.

## 2. Pilares

1. **Verdad biológica legible.** Todo lo que ocurre tiene explicación real. Las simplificaciones se marcan como [D] en `docs/BIOLOGIA.md`.
2. **Emergencia sobre guion.** El nido, los rastros y la división del trabajo salen de reglas locales.
3. **Respeto por la atención.** Funciona solo, no castiga la ausencia de golpe, avisa con discreción y consume poco.
4. **Pequeño pero nítido.** Pixel art fino: una hormiga de 8–9 px tiene que leerse como hormiga.
5. **Influencia, no control.** Las órdenes son condiciones del formicario, prioridades y feromonas. Nunca «mover unidad».

## 3. Público

- **Principal:** gente que trabaja o estudia con el ordenador y juega a *desktop companions* (*Rusty's Retirement*, *Tiny Pasture*).
- **Secundario:** aficionados a la cría de hormigas y fans de *SimAnt* o *Empires of the Undergrowth* que buscan algo contemplativo.
- **Terciario:** divulgación y docencia de biología.

## 4. Bucles de juego

| Bucle | Duración | Qué hace el jugador |
|---|---|---|
| Micro | 5–60 s, con foco | Mirar, pasar la lupa, leer qué hace una obrera, pintar un rastro |
| Sesión | 2–10 min, varias veces al día | Leer el diario, rellenar comedero o agua, ajustar calor o prioridad |
| Idle | horas o días | La colonia vive sola; con el juego cerrado, la resolución offline lo resume al volver |
| Macro | semanas reales | Fundación → crecimiento → madurez → vuelo nupcial (prestigio) → nueva colonia |

## 5. Progresión

| Etapa | Disparador | Qué aparece | Estado |
|---|---|---|---|
| 0. Reina fundadora | Inicio | Excava la cámara, sella la entrada, pone el primer lote | ✅ |
| 1. Nanitics | Primera eclosión (~día 40 a 24–28 °C) | Reabren la entrada, forrajeo, granero | ✅ |
| 2. Colonia joven | ≥ 50 obreras | Obreras medias, varias cámaras | ✅ |
| 3. Colonia establecida | ≥ 100 obreras | Obreras mayores (molienda), basurero, diapausa | ✅ |
| 4. Colonia madura | ≥ 1.000 obreras y ≥ 1 año | Producción de sexuados (alados) | ⬜ |
| 5. Vuelo nupcial | Alados + septiembre/octubre + lluvia | Prestigio: nueva reina con rasgos heredados | ⬜ |

## 6. Mecánicas

### 6.1 Ciclo de vida ✅
- **Fundación claustral.** La reina excava una galería y una cámara, sella la entrada con un tapón de tierra y vive de sus reservas (barra de reservas). Pone un lote de 13–19 huevos.
- **Huevo → larva → pupa → adulta**, con una tasa dependiente de la temperatura (modelo de grados-día, ver SIMULACION §4). Las larvas comen: durante la fundación, de las reservas de la reina; después, pan de hormiga.
- **Nanitics.** Las primeras obreras son más pequeñas, más lentas y viven menos.
- **Castas por tamaño de colonia.** Menores siempre; medias desde 50 obreras; mayores desde 100. Las larvas mal alimentadas salen menores.
- **Polietismo por edad y casta.** Las jóvenes cuidan la cría, las veteranas forrajean y las mayores muelen.

### 6.2 Tiempo (ADR-002) ✅
Las hormigas se mueven a velocidad real y el calendario corre a la escala elegida:

| Modo | Escala | Primera obrera | Un año |
|---|---|---|---|
| Realista | ×1 | ~6 semanas reales | 1 año real |
| Acompañante (por defecto) | ×24 | ~40 h reales | ~15 días reales |
| Acelerado | ×96 | ~10 h reales | ~4 días reales |

El calendario arranca en la fecha real del sistema. Diapausa invernal automática del 1 de diciembre al 31 de enero, a 14 °C.

### 6.3 Excavación emergente ✅
- El suelo es una rejilla de 640×240 celdas de 1 px (~1 mm) con capas de tierra vegetal, tierra, arcilla y piedras.
- El **plan de nido** solo marca *dónde* hay estímulo de excavación: galerías (cápsulas) y cámaras (elipses) que crecen según el espacio que pide la colonia. El orden y la forma final emergen de qué frentes alcanzan antes las excavadoras.
- Las excavadoras arrancan bolitas de tierra, las suben y las tiran junto a la entrada. Ahí se forma un **montículo** con física de arena que se erosiona poco a poco.
- Con mucho déficit de espacio se abren varios frentes a la vez.

### 6.4 Forrajeo y economía de semillas ✅
- Semillas del comedero y de los mechones de hierba (estacionales) → granero → **molienda** (las mayores, sobre todo) → pan de hormiga → larvas.
- Las cáscaras y los cadáveres se llevan al **basurero**, fuera del nido.
- Las forrajeras que vuelven con comida dejan **feromona de rastro**; las que salen eligen lado según el rastro (reclutamiento). La intensidad depende de la riqueza de la fuente.
- Solo se forrajea de día (especie diurna), por encima de 14 °C y fuera de la diapausa.

### 6.5 Órdenes del cuidador

| Herramienta | Efecto | Estado |
|---|---|---|
| Comedero +500 | Añade semillas | ✅ |
| Agua | Rellena el depósito (120 ml como máximo) | ✅ |
| Calor sí/no | +3 °C al nido | ✅ |
| Prioridad: Equilibrio / Crecer / Acumular / Excavar | Multiplica los estímulos de las tareas | ✅ |
| Pincel de feromona | Rastro artificial en la superficie (se evapora en unos 15 min) | ✅ |
| Lupa | Amplía ×3 y describe la hormiga o el lugar | ✅ |
| Marca de excavación | Sugerir dónde ampliar el nido | ⬜ |
| Humidificar o ventilar por zona | Control local de la humedad | ⬜ |

### 6.6 Problemas lentos 🟡
Avisos en el diario con antelación: comedero vacío ✅, menos de 5 días de reservas ✅, hambre ✅, sustrato seco (cría que se deseca) ✅, moho en el granero por exceso de humedad ✅, falta de espacio ✅, depósito de agua vacío ✅. Pendiente ⬜: cadáveres acumulados (patógenos), sobrecalentamiento en verano con la manta puesta.

### 6.7 Vuelo nupcial = prestigio ⬜ (fase alpha)
- La colonia madura produce gines y machos en verano. El vuelo solo es posible en **septiembre u octubre, al día siguiente o a los 2–3 días de una lluvia, con más de 20 °C** (Gómez y Abril, 2012). En el formicario, el jugador abre la tapa y ve el vuelo.
- **Mecánica de los dos linajes** (*M. barbarus* tiene hibridogénesis social: obreras híbridas Mbar1×Mbar2 y reinas de linaje puro). La nueva reina necesita esperma de **su** linaje (para futuras reinas) y del **otro** (para obreras). Si le falta el del otro linaje, la fundación fracasa porque no puede producir obreras.
- **Herencia:** rasgos acotados al ±10 % (fecundidad, proporción de mayores, tolerancia a la sequía, agresividad).
- **Reinicio suave:** la colonia vieja pasa al «álbum de colonias»; no se borra.

### 6.8 Condiciones de fallo
| Fallo | Causa | Estado |
|---|---|---|
| Muerte de la reina | Vejez (15–25 años), reservas agotadas en la fundación o hambre prolongada (más de 25 días) | ✅ |
| Fundación fallida | Reservas agotadas antes de la primera obrera | ✅ |
| Colapso | Hambre, moho o desecación mantenidos | ✅ (avisos) |

**Regla de no castigo:** en la resolución offline la reina no muere salvo por vejez, el hambre se acota y las crisis quedan como aviso para cuando vuelvas.

### 6.9 Ecosistema ⬜ (post-vertical slice)
Colonias vecinas, depredadores (arañas *Zodarion*), hormiga argentina como amenaza invasora, lluvia que inunda galerías y rescate por estridulación. Ver `docs/BIOLOGIA.md` §5–6.

## 7. Economía idle

- Recursos: semillas (granero), pan de hormiga, reservas de la reina, agua y humedad, espacio excavado, población por casta.
- **Sin moneda artificial.** Los desbloqueos llegan con hitos biológicos y con el cuaderno de campo (observar un comportamiento con la lupa por primera vez ⬜).
- Curva objetivo en modo acompañante: unas 10 obreras al final del primer otoño simulado, unas 120 a los 4 meses simulados (unos 5 días reales) y cientos el segundo año.

## 8. Onboarding

1. Al empezar, el diario explica en dos frases que la reina se arranca las alas y excava. ✅
2. Ayuda (H) con herramientas, tiempo y teclas. ✅
3. Pistas contextuales en el cuaderno: lupa, modo franja, comedero y prioridad ⬜.

## 9. Controles

| Acción | Entrada |
|---|---|
| Escala de tiempo | 1 / 2 / 3 o botón de escala |
| Feromonas, lupa, info, diario, ayuda | F, L, I, J, H |
| Ventana ↔ franja | F11 |
| Desplazarse | Rueda o arrastrar con el botón derecho |
| Zoom (×1–×4) | + / − |
| Pintar rastro | Botón *Pincel* + clic izquierdo en la superficie |
