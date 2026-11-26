# lang-detect.nu — the pure detector: an accent is Spanish; two univocal words
# are Spanish even without accents; a basename from the sweep is Spanish; and
# the lang-ok pragma is the only escape hatch.
# lang-ok: test fixtures (the asserted strings are Spanish on purpose)
use std/assert
use ../../lib/lang-detect.nu *

assert (spanish-line? 'qué es una mónada y para qué sirve') 'an accent is enough'
assert (spanish-line? 'por que chat_timeout_s no funcionaba y quien cortaba antes') 'two univocal words without accents'
assert (spanish-line? 'there is a mensaje and a usuario in the log') 'Spanish identifiers count as words'
assert (not (spanish-line? 'which advisory lock id does the migration runner take?')) 'English is not Spanish'
assert (not (spanish-line? 'the menu mentions con artist once')) 'ambiguous English look-alikes stay out'
assert (not (spanish-line? 'see paragraph para. 3 of the paper')) 'one borrowed word is not a Spanish line'

assert (spanish-name? '00-hoja-de-ruta.md') 'a Spanish word between separators'
assert (spanish-name? 'wipe-mensajes.nu') 'a Spanish word after a hyphen'
assert (not (spanish-name? 'memories-core.json')) 'English names pass'
assert (not (spanish-name? 'plan-compass.md')) 'the renamed target passes'

assert (has-pragma? ['<!-- lang-ok: verbatim quote -->' '# title']) 'pragma in the head'
assert (not (has-pragma? ['# title' 'body'])) 'no pragma, no escape'

let coarse: string = (coarse-pattern)
assert ($coarse | str contains 'que') 'the coarse pass carries the words'
assert ('por que no funciona' =~ $coarse) 'the coarse pass sees unaccented Spanish'

print 'lib/lang-detect ok — accents, unaccented pairs, basenames, pragma'
