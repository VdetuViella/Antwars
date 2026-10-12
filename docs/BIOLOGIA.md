# Referencia biológica

Procedencia de cada dato: **[C]** científico publicado · **[A]** criadores o tiendas especializadas (útil, pero menos fiable) · **[D]** decisión de diseño. Los números que usa el código viven en `data/species/<id>.json`; este documento explica de dónde salen.

## 1. *Messor barbarus* — especie de la 1.0

### Distribución y ecología
- Mediterráneo occidental. En la Península Ibérica está en casi todo el territorio salvo el noroeste, en pastizales y lugares secos y soleados [C, Gómez y Abril 2012].
- Es la hormiga más común en los cereales de secano del noreste de España y causa entre el 50 y el 100 % de las pérdidas de semillas de malas hierbas en esos campos [C, Westerman et al. 2012; Torra et al. 2016].
- Sus caminos de forrajeo, permanentes y temporales, miden de 1 a 30 m [C, Cerdan 1989]. Los basureros exteriores modifican el banco de semillas del pastizal [C].

### Morfología y castas
- Obreras muy polimórficas, de 3 a 14 mm. Menores de 3–6 mm, negras. Mayores de 8–14 mm, con la cabeza grande y rojiza [A].
- Alados: machos de 7–12 mm, reinas de 9–15 mm [C, Gómez y Abril 2012].
- Medias a partir de unas 50 obreras y mayores a partir de unas 100 [A] → `castes.unlock_*`.
- **Hibridogénesis social** [C, Norman et al. 2016, *Biol. Lett.* 12: 20160542]: dos linajes crípticos (Mbar1 y Mbar2). Los cruces entre linajes dan obreras estériles; los cruces dentro de un linaje dan reinas. Romiguier et al. (2017) lo confirman en todas las poblaciones estudiadas y señalan que, siendo granívoras estrictas, no pueden decidir la casta por la dieta de la larva. Es la base del prestigio (GDD §6.7).

### Colonia y fundación
- Monógina [A, consenso de criadores]. Colonias adultas de 10.000–15.000 obreras [A]; las cifras mayores que dan algunas tiendas no tienen respaldo.
- Fundación claustral independiente [A/C]: la reina no come y cría la primera camada con sus reservas.

### Desarrollo (→ `development`)
| Etapa | Criadores [A] | Modelo del juego a 26–30 °C [D] |
|---|---|---|
| Huevo | 10–15 días | 9,6 días |
| Larva | 10–20 días | 12,0 días |
| Pupa (desnuda, sin capullo) | 10–25 días | 13,6 días |
| **Total** | 30–50 días a 24–28 °C · 60–90 días a 20 °C | ~35 días a 26 °C · ~44 días a 24 °C · ~88 días a 20 °C |

Modelo de grados-día con meseta [D]: `tasa(T) = (T − 16)/(26 − 16)` entre 16 y 26 °C, 1 entre 26 y 30 °C, y cae linealmente hasta 0 a 36 °C (`SpeciesDef.dev_rate`). Calibrado con `test_dev_rate_calibration`.

### Longevidad (→ `lifespan_days`)
- Reina: 15–25 años [A]; no hay registro científico de la máxima. Media del juego: 7.300 días ±25 %.
- Obreras: 1–3 años [A] (media de 730 días). Nanitics: 240 días [D].

### Clima del nido (→ `climate`)
- Nido óptimo a 24–28 °C [A]. Cría y reina con 50–70 % de humedad relativa. **Granero seco**, al 10–50 % de humedad, para que las semillas no germinen ni enmohezcan [A].
- Diapausa de noviembre a febrero, a unos 15 °C, mínimo 45 días [A]. En el juego, la hibernación automática va del 1 de diciembre al 31 de enero a 14 °C.
- Puesta solo por encima de 18 °C [D]. Forrajeo por encima de 14 °C en superficie [D].

### Dieta y consumo (→ `consumption_seeds_per_day`)
Granívora: tritura semillas para hacer «pan de hormiga» con el que alimenta a las larvas, y lo complementa con insectos [A/C]. Los consumos por casta y día son [D], ajustados para que una colonia de 100 obreras gaste unas 10–20 semillas al día.

### Vuelo nupcial (→ `nuptial_flight`)
Gómez y Abril (2012, *Myrmecological News* 16: 25–29), con 123 observaciones de la base de datos «Alados» de lamarabunta.org entre 2003 y 2009 [C]:
- El 93 % de los vuelos ocurre en **siete semanas de septiembre y octubre**.
- **Siempre después de un frente de lluvia**, con el pico 2–3 días después, ya despejado.
- Lluvia fuerte el día anterior, más de 20 °C, cielo despejado y poco o ningún viento.
- Los vuelos se agrupan en *clusters* de 3,9 ± 0,8 días; un mismo frente sincroniza vuelos a hasta 1.075 km de distancia.

### Comportamiento
- Las mayores recogen las semillas grandes; el tamaño de la semilla modula el reclutamiento [C, *Behav. Processes* 70: 289–300]. Hay transporte cooperativo secuencial [C, *Insectes Soc.* 46: 119–125].
- Myrmicinae con órgano estridulador [C]: base de la futura mecánica de rescate tras derrumbes.
- Necroforesis: los cadáveres se sacan al basurero [C, comportamiento general].

## 2. *Polyergus rufescens* — modo difícil (beta)
- Obreras monomorfas de 4,67–6,98 mm (media 6,14) [C, Trager 2013]; reinas de 8–10 mm [C].
- **Esclavista obligada:** sus mandíbulas en hoz no sirven para forrajear ni cuidar la cría.
- Hospedadoras (número de observaciones): *Formica cunicularia* 16, *F. fusca* 12, *F. rufibarbis* 10, *F. clara* 3, *F. gagates* 3, *F. cinerea* 1 [C]. *F. rufibarbis* se defiende mejor y suele matar a las reinas parásitas [C].
- **Fundación por usurpación:** la reina entra en el nido hospedador, mata a la reina residente, es aceptada y se queda con la cría [C, Mori et al. 1995]. La secreción de la glándula de Dufour reduce los ataques [C].
- **Incursiones** [C, Mori, Grasso y Le Moli 1991]: 38 en 32 días observados, con 11 fracasos (~29 %, cálculo propio), a última hora de la tarde y tras una fase de exploración. Las atacantes excavan junto a la entrada del nido objetivo. Distancia máxima registrada: 55 m [C, Czechowski]. Temporada de 6–8 semanas cada verano; la colonia vive 10–15 años.
- ⚠️ Antes de calibrar, conseguir los textos completos de Mori 1991 y Le Moli 1994. No usar las cifras de *Polyergus* norteamericanos.

## 3. *Aphaenogaster senilis* — post-1.0
Monógina y monándrica; se reproduce **solo por fisión**: las reinas tienen alas vestigiales [C]. Colonias de unas 1.300 obreras [C, Boulay 2007]. Su feromona de reina inhibe la producción de gines y, en colonias grandes, se diluye y aparecen reinas nuevas [C]. Puede criar reinas de reemplazo a partir de larvas [C].

## 4. *Lasius niger* — post-1.0
Reina con longevidad récord de 28 años [C, Kutter y Stumper 1969]. Colonias de 4.000–7.000 obreras [C/A]. Pleometrosis en el 18 % de los casos [C]. Ganadera de pulgones (trofalaxia, buche social).

## 5. *Pheidole pallidula* — vecina / post-1.0
Dimórfica: las menores sujetan al intruso por las patas y reclutan; los soldados lo matan, con una defensa que se adapta al número de intrusos [C, Detrain y Pasteels 1992]. Sus diferencias de umbral por casta [C, 1991] son la base del modelo de umbrales.

## 6. *Linepithema humile* — amenaza invasora (no jugable)
Mínimo térmico crítico de 0–0,8 °C, máximo de 38–40 °C; los huevos no se desarrollan por encima de 32 °C [C, Abril et al. 2010]. Deja de forrajear a 40–44 °C [C, Holway]. Forma una supercolonia europea de más de 6.000 km. Prefiere ambientes húmedos.

## 7. Comportamientos transversales
- **Feromonas:** rastro, alarma, reina, cría, territorio.
- **Trofalaxia**, fuerte en Formicinae; en *Messor* domina el pan de hormiga sólido.
- **Higiene:** basurero y cementerio; hongos y moho como eventos.

## 8. Fuentes principales
- Gómez C., Abril S. (2012). Nuptial flights of the seed-harvester ant *Messor barbarus* in the Iberian Peninsula. *Myrmecol. News* 16: 25–29.
- Norman V. et al. (2016). Cryptic lineages hybridize for worker production in the harvester ant *Messor barbarus*. *Biol. Lett.* 12: 20160542.
- Romiguier J. et al. (2017). Convergent evolution of social hybridogenesis in *Messor* harvester ants. *Mol. Ecol.*
- Bonabeau E., Theraulaz G., Deneubourg J.-L. (1996). Quantitative study of the fixed threshold model. *Proc. R. Soc. B* 263: 1565–1569.
- Buhl J. et al. (2004). Self-organized digging activity in ant colonies. *Naturwissenschaften* 91: 602–606.
- Mori A., Grasso D. A., Le Moli F. (1991). Eco-ethological study on raiding behaviour of *Polyergus rufescens*. *Ethology* 88: 46–62.
- Trager J. C. (2013). Global revision of the dulotic ant genus *Polyergus*. *Zootaxa* 3722.
- Boulay R. et al. (2007). *Behav. Ecol. Sociobiol.* (fisión en *A. senilis*).
- Detrain C., Pasteels J. M. (1992). *Behav. Ecol. Sociobiol.* 29: 405–412.
- Abril S. et al. (2010). *J. Insect Sci.* 10: 97.
- Guías de cría: ant-shack, antsdavey, bestantsuk, antstore, fourmiculture (datos [A]).
