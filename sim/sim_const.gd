class_name SimConst
extends RefCounted
## Constantes compartidas de la simulación. Sin dependencias de nodos ni escenas.

# --- Mundo ---
const WORLD_W := 640            ## celdas (1 celda = 1 px lógico ≈ 1 mm)
const WORLD_H := 240
const SURFACE_Y := 60           ## altura media del suelo (filas por encima = aire / outworld)
const NAV_CELL := 2             ## tamaño de celda de la rejilla de navegación
const PHER_CELL := 4            ## tamaño de celda de las feromonas

# --- Tiempo ---
const BEHAVIOUR_DT := 0.1       ## paso fijo de comportamiento (s de comportamiento)
const BIO_STEP_SECONDS := 600.0 ## paso fijo de biología (s biológicos = 10 min)
const SECONDS_PER_DAY := 86400.0

# --- Materiales del suelo ---
enum Mat { AIR = 0, TOPSOIL = 1, SOIL = 2, CLAY = 3, LOOSE = 4, ROCK = 5, MIDDEN = 6, PLUG = 7 }

# --- Castas ---
enum Caste { MINOR = 0, MEDIA = 1, MAJOR = 2, QUEEN = 3 }
const CASTE_KEYS := ["minor", "media", "major", "queen"]

# --- Tareas (asignación por umbrales de respuesta) ---
enum Task { REST = 0, NURSE = 1, FORAGE = 2, DIG = 3, MILL = 4, CLEAN = 5, QUEEN = 6 }
const N_TASKS := 6              ## tareas elegibles por obreras (sin QUEEN)
const TASK_KEYS := ["rest", "nurse", "forage", "dig", "mill", "clean", "queen"]

# --- Lo que lleva una hormiga en las mandíbulas ---
enum Carry { NONE = 0, SEED = 1, SOIL = 2, BREAD = 3, HUSK = 4, CORPSE = 5 }

# --- Campos de distancia de navegación ---
enum Field { ENTRANCE = 0, BROOD = 1, GRANARY = 2, DIG = 3, REST = 4, QUEEN = 5 }
const N_FIELDS := 6

# --- Escalas de tiempo (segundos biológicos por segundo real) ---
const TIME_SCALES := {
	"realista": 1.0,
	"acompanante": 24.0,
	"acelerado": 96.0,
}
