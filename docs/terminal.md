# Pestaña TERMINAL: Claude Code en el teléfono

Claude Code oficial (login Pro/Max) corriendo en el teléfono, manejado desde una pestaña pixel con mando.
Decisiones del planeamiento: motor en Termux → proot Debian; UI propia sobre `stream-json`; el launcher es
servidor MCP (permisos, Shizuku, apps, pestañas). La búsqueda tipo terminal que había antes es una vista
más de esta pestaña.

```
Launcher (Flutter)                                   Termux → proot-distro debian
 pestaña TERMINAL ── TCP 127.0.0.1:8765 (NDJSON) ──► bridge.js ──spawn──► claude -p (stream-json)
 servidor MCP     ◄── HTTP 127.0.0.1:8766/mcp ─────────────────────────── (--mcp-config, permisos)
 MainActivity.kt: Shizuku (shell uid) + RUN_COMMAND de Termux
```

Los dos puertos solo escuchan en loopback, pero cualquier app del teléfono llega a loopback: **todo pedido
lleva el token** que genera el launcher (prefs `claude_token`) y le pasa a Termux al arrancar el puente.

## Puesta en marcha (una vez)

1. Instalar Termux (F-Droid o GitHub, **no** Play Store) y Shizuku. Arrancar Shizuku (depuración inalámbrica).
2. En Termux: `echo allow-external-apps=true >> ~/.termux/termux.properties` (sin esto ninguna app le puede
   mandar comandos).
3. En la pestaña TERMINAL → INSTALAR: el launcher pide el permiso "Ejecutar comandos en Termux" y manda
   `setup.sh` (va como asset del launcher) a una sesión visible de Termux. Instala proot-distro, Debian,
   node, git y Claude Code; con `--toolchain`, además JDK 21, Android SDK, Flutter 3.35.5 (la de la PC) y el
   `aapt2` linux-arm64 de Google Maven (`android.aapt2FromMavenOverride` en `~/.gradle/gradle.properties`,
   que además baja el heap de Gradle a 3 GB).
   **En arm64 solo sale `flutter build apk --debug`**: Flutter no publica `gen_snapshot` linux-arm64.
4. PERMISO SHIZUKU: además apaga el límite de procesos de Android 12+ (phantom process killer).
5. LOGIN: abre una sesión de Termux con `claude` dentro de Debian para hacer `/login` una vez.
6. Para que los builds del teléfono se instalen encima de los de la PC: misma keystore. Desde la PC,
   `adb push %USERPROFILE%\.android\debug.keystore /sdcard/Download/` y `setup.sh` la copia a `~/.android/`.

## Puente (`termux/bridge.js`, corre dentro de Debian)

`node bridge.js` escucha en `127.0.0.1:8765`. Lee el token de `~/.pixel/token`. Protocolo: una línea JSON por
mensaje, en los dos sentidos.

Cliente → puente:

| Mensaje | Qué hace |
|---|---|
| `{"token":"…"}` | Primera línea, obligatoria. Si no coincide, cierra. |
| `{"op":"sessions"}` | Lista de sesiones. |
| `{"op":"open","id":"<uuid>","cwd":"/root/proyecto"}` | Se suscribe a la sesión. Primero reenvía la historia (líneas `user`/`assistant` del `.jsonl` de Claude), después los eventos en vivo. No arranca el proceso. |
| `{"op":"send","id":"<uuid>","cwd":"…","text":"…"}` | Manda un mensaje. Si el proceso no está vivo, lo arranca (`--session-id` si la sesión es nueva, `--resume` si ya existe). |
| `{"op":"stop","id":"<uuid>"}` | Interrumpe el turno (`control_request` `interrupt`). |
| `{"op":"close","id":"<uuid>"}` | Termina el proceso (la sesión queda en disco para retomarla). |

Puente → cliente:

| Mensaje | Cuándo |
|---|---|
| `{"op":"sessions","list":[{"id","cwd","title","updated","running"}]}` | Respuesta a `sessions`. `title` = primer mensaje del usuario, recortado. |
| `{"op":"event","id":"<uuid>","event":{…}}` | Cada línea que escribe `claude` (o de la historia). `event` es el JSON tal cual. |
| `{"op":"exit","id":"<uuid>","code":0}` | El proceso terminó. |
| `{"op":"error","message":"…"}` | Algo falló (ej. `claude` no instalado). |

Las sesiones viven en el puente, no en la conexión: si el launcher se reinicia (por ejemplo, al instalarse un
build nuevo de sí mismo), Claude sigue trabajando y al reconectar se retoma la historia.

El MCP (permisos) sí vive en el launcher: si Android lo mata, las tools de un turno en curso fallan
(`ECONNREFUSED`). Por eso, con un turno en curso el launcher levanta un servicio en primer plano
(`KeepAlive`, aviso "Claude está trabajando"). Y cuando un cliente se autentica, el puente cierra los `claude`
que no tienen turno en curso: quedaron con la conexión MCP vieja, y el próximo `send` los retoma con
`--resume`. `bridge.js` va como asset del launcher; para cargar uno nuevo: pasos → REINICIAR PUENTE.

Claude se lanza con:

```
claude -p --input-format stream-json --output-format stream-json --verbose \
  --mcp-config '{"mcpServers":{"launcher":{"type":"http","url":"http://127.0.0.1:8766/mcp?session=<uuid>&cwd=<carpeta>","headers":{"Authorization":"Bearer <token>"}}}}' \
  --permission-prompt-tool mcp__launcher__approve  (--session-id <uuid> | --resume <uuid>)
```

Mensaje de usuario por stdin: `{"type":"user","message":{"role":"user","content":"…"}}`.

## Servidor MCP del launcher (`lib/claude.dart`)

HTTP en `127.0.0.1:8766/mcp`, JSON-RPC sin SSE (responde `application/json`; las notificaciones, `202`).
Exige `Authorization: Bearer <token>` (si no, `401`). Métodos desconocidos con `id` → error `-32601`.

| Tool | Qué hace | Confirmación |
|---|---|---|
| `approve` | La de `--permission-prompt-tool`: recibe `{tool_name, input, tool_use_id}` y devuelve `{"behavior":"allow","updatedInput":…}` o `{"behavior":"deny","message":…}` | según la política |
| `android_shell` | Comando como usuario shell vía Shizuku: `settings`, `pm`, `cmd`, `dumpsys`, `am`… Devuelve código, stdout y stderr | lecturas libres, el resto cada vez |
| `install_apk` | `setsid nohup pm install -r -d <path>` vía Shizuku (desacoplado: Shizuku mata los procesos de la app cuando ella muere). Responde antes de instalar. Log en `/data/local/tmp/pixel-install.log`. El APK tiene que estar en `/sdcard` | cada vez |
| `apps` | Apps instaladas con aperturas | libre |
| `launch_app` | Abre una app con `store.launch` | libre |
| `tabs_get` / `tabs_set` | Lee o reemplaza las pestañas del launcher (el mismo JSON que `tabStore`) | `tabs_set` cada vez |

## Política de permisos (`decide` en `lib/claude.dart`, con tests)

Lectura libre; escritura con una confirmación que explica las consecuencias. Se agrupa lo de bajo riesgo:

- **Libre:** `Read`, `Glob`, `Grep`, `LS`, `WebFetch`, `WebSearch`, `TodoWrite`, `Task`… (todo lo que no escribe),
  y en `android_shell` los comandos de lectura (`settings get|list`, `dumpsys`, `pm list|path`, `getprop`,
  `cmd package list`) sin `;`, `&`, `|`, `>`, `` ` `` ni `$(`.
- **Una vez por turno:** `Edit`/`Write`/`NotebookEdit` dentro de la carpeta de la sesión, y `Bash` sin
  comandos peligrosos. Al aprobar, queda aprobado lo de bajo riesgo hasta el próximo mensaje del usuario.
- **Cada vez:** escribir fuera de la carpeta de la sesión, `Bash` con `rm`, `mv` o redirección fuera del
  proyecto, `git push`, `git reset --hard`, `curl … | sh`, `sudo`, `chmod -R`, `dd`, `adb`; `android_shell` que
  no sea de lectura, `install_apk`, `tabs_set`, y cualquier tool MCP desconocida.

El diálogo dice qué tool, sobre qué (archivo o comando) y qué puede romper; A permite, B deniega.

**Modo AUTO** (botón en el chat, `"auto": true` en la config de la pestaña): el MCP permite todo sin preguntar,
incluido `install_apk`, `android_shell` y escribir fuera del proyecto. Vale para la sesión que muestra esa pestaña.

## Estado en la config de la pestaña

`{"kind":"terminal","name":"TERMINAL","view":"chat"|"buscar"|"app","session":"<uuid>","cwd":"/root/…","auto":false}`
(sin `view`, el chat). `app` muestra claude.ai con la utilidad Web y, si está instalada, abre la app oficial o
le comparte un texto (Android no deja incrustar la pantalla de otra app). El
proceso y la historia viven en el puente; la pestaña solo recuerda cuál mirar.

## Ciclo completo: compilar el launcher en el teléfono

El repo no tiene remoto: para tenerlo en el teléfono, desde la PC
`git bundle create launcher.bundle --all && adb push launcher.bundle /sdcard/Download/`, y en una sesión
de Claude con carpeta `/root/launcher`: "cloná /sdcard/Download/launcher.bundle acá". Después, por ejemplo:
"cambiá X, compilá con `flutter build apk --debug --split-per-abi --target-platform android-arm64`,
copiá `build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk` a /sdcard/Download/ e instalalo".
**Siempre `--split-per-abi`, en la PC y en el teléfono:** suma 2000 al versionCode en arm64 (2002). Un build
sin él sale con versionCode 2 y Android rechaza el downgrade (`-d` no sirve si el instalado es release). Desde
la PC, por adb Wi-Fi, conviene el release arm64 (17 MB): el debug pesa 158 MB y la conexión se corta.
Instalar el launcher lo cierra; Android lo vuelve a abrir, la pestaña reconecta y la sesión sigue (vive en
Termux). Si el build nuevo no arranca, el launcher del sistema queda de respaldo.
