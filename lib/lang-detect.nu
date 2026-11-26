# lang-detect.nu — the pure half of the English gate.
# lang-ok: detector input (the Spanish word lists are the gate's own data)
# Owner law 2026-11-06 and full sweep 2026-11-26: work products are English.
# This module answers whether a line, a basename or a file head still says
# Spanish. No IO here; scripts/langcheck.nu walks the disk and calls it.
export const ACCENT: string = '[áéíóúüñ¿¡]'

# Spanish in almost any context. Deliberately excluded: single letters and
# English look-alikes (no, o, y, es, son, la, el, de, con, sin, version,
# total, sidecar, leer).
export const UNIVOCAL: list<string> = [
    'que' 'para' 'por' 'porque' 'cuando' 'desde' 'hasta' 'también' 'tambien'
    'además' 'ademas' 'según' 'segun' 'código' 'codigo' 'opción' 'opcion'
    'función' 'funcion' 'archivo' 'archivos' 'mensaje' 'mensajes' 'usuario'
    'usuarios' 'solamente' 'entonces' 'devuelve' 'permite' 'hacer' 'tenemos'
    'puede' 'pueden' 'hay' 'esto' 'esta' 'estos' 'estas' 'aquí' 'aqui'
    'así' 'asi' 'través' 'traves' 'más' 'los' 'las' 'del' 'una' 'unos'
    'unas' 'sobre' 'entre' 'hola' 'correo' 'funciona'
]

# Words that make a basename Spanish (curated in the 2026-11-26 sweep).
export const NAME_WORDS: list<string> = [
    'mensajes' 'usuarios' 'archivo' 'archivos' 'estado' 'vigilia' 'huella'
    'ingesta' 'grupo' 'grupos' 'filas' 'buscar' 'limpiar' 'verifica' 'primer'
    'migracion' 'incidente' 'robustez' 'foco' 'reencarnacion' 'hoja' 'ruta'
    'brujula' 'mapa' 'diccionario' 'ecosistema' 'pendiente' 'tarea' 'salida'
    'entrada' 'linea' 'columna' 'obtener' 'cargar' 'guardar' 'escribir'
    'contar' 'corrida' 'adjuntos' 'huerfanas'
]

# A word with Unicode-aware boundaries, case-insensitive.
export def word-pattern [word: string]: nothing -> string {
    ('(?i)(?<![\wáéíóúüñ])(' + $word + ')(?![\wáéíóúüñ])')
}

# A line is Spanish when it carries an accent, or when two or more univocal
# Spanish words appear together: the unaccented pair is still caught.
export def spanish-line? [line: string]: nothing -> bool {
    if ($line =~ $ACCENT) { return true }
    let hits: list<string> = ($UNIVOCAL | where {|w| $line =~ (word-pattern $w) })
    ($hits | length) >= 2
}

# A basename is Spanish when it carries an accent or a curated Spanish word,
# alone or between separators (wipe-mensajes.nu, 00-hoja-de-ruta.md).
export def spanish-name? [name: string]: nothing -> bool {
    let stem: string = ($name | path parse | get stem | str lowercase)
    if ($stem =~ $ACCENT) { return true }
    let hits: list<string> = ($NAME_WORDS | where {|w| $stem =~ ('(?i)(^|[-_.])(' + $w + ')([-_.]|$)') })
    not ($hits | is-empty)
}

# The escape hatch: a file that keeps Spanish on purpose says so in its head.
export def has-pragma? [head: list<string>]: nothing -> bool {
    $head | any {|l| $l =~ 'lang-ok:' }
}

# One regex that narrows a file to candidate lines. Rust regex has no
# lookbehind, so the coarse pass uses consumer boundaries; the precise answer
# still comes from spanish-line?.
export def coarse-pattern []: nothing -> string {
    let words: string = ($UNIVOCAL | str join '|')
    ('(?i)((' + $ACCENT + ')|(^|[^\wáéíóúüñ])(' + $words + ')([^\wáéíóúüñ]|$))')
}
