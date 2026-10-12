# Dirección de arte y audio

## 1. Escala y resolución
- Mundo lógico: 1 celda = 1 px ≈ 1 mm. Escala siempre **entera**, filtrado *nearest* y ajuste al píxel (`snap_2d_transforms_to_pixel`).
- **Zoom automático** en modo ventana: el mayor entero que cabe (×2 en 1280×560, ×3 en 1920×1040). El formicario queda centrado sobre una balda de madera. Con +/− se pasa a zoom manual (×1–×8) y con 0 se vuelve al automático. En la franja, el zoom es manual (×2 por defecto).
- Modo ventana de 1280×560 (el formicario de 640×240 a ×2 más la barra de 34 px). La franja ocupa todo el ancho útil del monitor por unos 300 px de alto.

## 2. Hormigas (generadas por `tools/gen_sprites.py`)
**Cuerpo en perfil dibujado a mano** píxel a píxel para cada casta (gáster con brillo dorsal, pecíolo, mesosoma, cabeza y mandíbula). **Patas y antenas en líneas de 1 px** con fotogramas clave. Atlas de 600×120 con celdas de 24 px:

| Fila | Casta | Cuerpo | Rasgo |
|---|---|---|---|
| 0 | Menor | 13 px | Negra |
| 1 | Media | 16 px | Gáster y cabeza algo mayores |
| 2 | Mayor | 17 px | Cabeza grande y rojiza (el rasgo más reconocible) |
| 3 | Reina | 21 px | Gáster enorme, muñones alares |
| 4 | Nanitic | 11 px | Más pequeña |

- **Columnas:** 3 direcciones (E, NE, N) × 8 fotogramas + cadáver. El resto de direcciones se consigue volteando en el render.
- **Marcha en trípode** (6 fotogramas): la delantera y la trasera de un lado avanzan a la vez que la media del otro. El pie se levanta 1 px en la fase de vuelo. Las patas del lado lejano van en un tono más claro, desplazadas 1 px y en contrafase.
- **Reposo** (2 fotogramas): las antenas tantean (arriba / abajo); la reina «respira» (el gáster crece 1 px). Cada hormiga va con su propio desfase. Excavando o moliendo, el tanteo es más rápido.
- **Rotación NE y N con RotSprite:** Scale2x ×3 (8×), giro con vecino más cercano y reducción, rescatando el color mayoritario en los bloques con tinta. Así no se pierden las líneas de 1 px.
- **Ritmo:** el fotograma avanza ~0,9 por píxel recorrido, para que los pies no patinen.
- **Contorno de 1 px** en el shader (`ants.gdshader`), en un tono tierra claro al 55 %: separa hormigas solapadas.
- Las cargas van en un atlas de 96×8: semilla, tierra, pan, cáscara, cadáver, huevo, larvas, pupa, semilla de hierba y grano.

## 3. Suelo
- Rampas de 4 tonos por material elegidas con ruido determinista, más granos claros u oscuros sueltos.
- Oscurecimiento progresivo con la profundidad (hasta un −12 %).
- **Galerías claras** (sustrato iluminado tras el cristal) con oclusión ambiental junto a las paredes, para que las hormigas, casi negras, contrasten.
- Las paredes cortadas son más oscuras; la cara del suelo que da al cielo, más clara.

## 4. Decorado
Hierba que se mece y amarillea en verano, con espigas en temporada; comedero de plástico; tubo de agua con algodón y nivel visible; semillas; granero (pila de semillas en el suelo de la cámara); cría por tipos (huevos, larvas, pupas desnudas); marco de cristal con reflejos muy tenues. En modo ventana, la pared de la habitación cambia con la luz del día, de beige a azul noche. La pared va **detrás** del suelo para que el montículo se vea.

## 5. Interfaz
Paneles marrón oscuro semitransparentes con borde ocre y texto crema. Barra inferior de 34 px con botones de texto. Panel de información (fecha, población por castas, cría, granero, nido, plantilla por tareas), diario, ayuda y «mientras no estabas». Lupa circular ×3 con etiqueta de la hormiga o el lugar.

## 6. Pendiente ⬜
- Paleta maestra cerrada (32–48 colores) y revisión de contraste en la franja con fondos de escritorio claros y oscuros.
- Iconos pixel de 12×12 para la barra (sustituir el texto).
- Fuente pixel con glifos españoles.
- Alados (gine de 16 px, macho de 12 px) para el vuelo nupcial.
- Lluvia (gotas de 1×2), destellos al nacer obreras (desactivables).

## 7. Audio ⬜
Principio: el juego vive al fondo mientras trabajas, así que el audio es **opcional, bajo y no rítmico**.
- Por defecto: música apagada, ambiente al 30 % y efectos al 40 %. Silencio al perder el foco en el perfil «oficina».
- Ambiente en bucles de más de 3 minutos: grillos de noche, cigarras en verano y un granulado de tierra que crece con la actividad.
- Efectos solo cerca de la lupa: excavar, semilla cayendo en el granero, estridulación.
- Un motivo de 2–3 notas para «primera obrera», «vuelo nupcial» y «reina en peligro». Sin alarmas.
- Buses separados (Música / Ambiente / Efectos / Avisos). Mezcla de −23 a −20 LUFS y limitador en el maestro.
