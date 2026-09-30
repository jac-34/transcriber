# Transcriptor

Transcribe clases grabadas (en español) a texto legible con marcas de tiempo, sin internet y sin costo.
Funciona en Macs con chip Apple (M1 o posterior), 16 GB de RAM o más, y macOS 14 o más nuevo.

## Instalar

1. Descomprime `Transcriptor-x.y.z.zip` y arrastra `Transcriptor.app` a la carpeta Aplicaciones.
2. La primera vez, macOS va a decir que no puede verificar la app. Haz esto una sola vez:
   - Clic derecho sobre `Transcriptor.app` → **Abrir**. Si aparece solo "Cancelar/Mover a papelera", ve a
     **Ajustes del Sistema → Privacidad y seguridad**, baja hasta el mensaje sobre Transcriptor y toca **Abrir de todos modos**.
3. Al abrir por primera vez, la app descarga el modelo de transcripción (unos 3 GB, una sola vez). Necesita internet solo para esto.
   Después de descargarlo tarda un par de minutos en prepararlo. Desde ahí funciona sin conexión.

## Usar

- Arrastra los audios a la ventana o usa **Agregar audios** (⌘O). Puedes agregar varios; se procesan uno por uno.
- Formatos aceptados: m4a, mp3, wav, aac, aiff, caf, flac, mp4, mov. Las notas de voz `.opus` de WhatsApp en Android no funcionan; conviértelas primero.
- Una clase de 90 minutos tarda unos 26 minutos en modo **Preciso** o unos 3 en modo **Rápido** (Ajustes).
- Las transcripciones se guardan solas en `Documentos/Transcripciones` como `.md`. **Exportar** guarda una copia en `.md` o `.txt` donde quieras.
- **Buscar** (arriba a la derecha) resalta palabras dentro de la transcripción.

## Glosario

El modelo se equivoca con términos médicos ("hipocalemia" en vez de "hipokalemia"). El botón **Glosario** abre una lista que puedes editar:

```
# Un término por línea ayuda al modelo a escribirlo bien:
hipokalemia
enalapril
# Una corrección reemplaza lo que sale mal por lo correcto:
hipocalemia => hipokalemia
```

**Guardar y re-aplicar** corrige la transcripción seleccionada al instante, sin volver a transcribir.
Con el tiempo el glosario va a tener los términos de sus ramos y las transcripciones saldrán cada vez mejor.

## Si algo falla

Cada archivo muestra su propio error en la lista; los demás siguen. Si algo no funciona, manda el archivo
`~/Library/Logs/Transcriptor/transcriptor.log` (en el Finder: ⇧⌘G y pega la ruta).

## Para desarrollar

Requiere solo las Command Line Tools de Apple (no Xcode).

```
make test               # pruebas rápidas
make test-integration   # descarga el modelo pequeño y transcribe un clip sintético
make app                # arma dist/Transcriptor.app
make zip                # dist/Transcriptor-<versión>.zip para compartir
```
