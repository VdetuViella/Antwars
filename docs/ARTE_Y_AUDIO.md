# Dirección de arte y audio

## 1. Escala y resolución
- Mundo lógico: 1 celda = 1 px ≈ 1 mm. Escala entera (×1–×4, por defecto ×2), filtrado *nearest* y ajuste al píxel (`snap_2d_transforms_to_pixel`).
- Modo ventana de 1280×560 (el formicario de 640×240 a ×2 más la barra de 34 px). La franja ocupa todo el ancho útil del monitor por unos 300 px de alto.

## 2. Hormigas (generadas por `tools/gen_sprites.py`)
Modelo paramétrico (gáster, pecíolo, mesosoma, cabeza, mandíbulas, antenas acodadas y tres pares de patas) rasterizado con supermuestreo ×6 y umbral de cobertura. Atlas de 260×100 con celdas de 20 px:

| Fila | Casta | Longitud | Rasgo |
|---|---|---|---|
| 0 | Menor | 9 px | Negra |
| 1 | Media | 10 px | Gáster algo mayor |
| 2 | Mayor | 12,5 px | Cabeza ×1,75 y rojiza (el rasgo más reconocible) |
| 3 | Reina | 16 px | Tórax ancho y muñones alares |
| 4 | Nanitic | 8 px | Más pequeña |

- 3 orientaciones dibujadas (E, NE, N); el resto se obtiene volteando. 4 fotogramas de marcha (trípode alterno) y uno de cadáver.
- **Contorno de 1 px** en el shader (`ants.gdshader`), en un tono tierra claro al 55 % de opacidad: cuando dos hormigas se solapan, la de encima se separa de la de debajo.
- Cargas en un atlas de 96×8: semilla, tierra, pan, cáscara, cadáver, huevo, larvas, pupa, semilla de hierba y grano.
- Proporciones algo exageradas (cabeza y cintura) para que se lean a ×1 en 1080p.

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
