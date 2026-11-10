# Lo corre el launcher en Termux (no en Debian):
#   bash -c "<este archivo>" start "<contenido de bridge.js>" "<token>"
set -e
PID=$HOME/.pixel-bridge.pid
# proot-distro 5.x guarda el rootfs en containers/debian/rootfs: bridge.js y token entran por stdin, sin tocar esa ruta
printf '%s' "$1" | proot-distro login debian -- sh -c 'mkdir -p /root/.pixel && cat > /root/.pixel/bridge.js'
printf '%s\n' "$2" | proot-distro login debian -- sh -c 'umask 077; mkdir -p /root/.pixel; cat > /root/.pixel/token; chmod 600 /root/.pixel/token'
command -v termux-wake-lock >/dev/null && termux-wake-lock || true
# Si había un puente corriendo, lo mata (con setsid el pid es líder de grupo: cae todo el árbol)
if [ -f "$PID" ]; then
  kill -- -"$(cat "$PID")" 2>/dev/null || kill "$(cat "$PID")" 2>/dev/null || true
  sleep 1
fi
# setsid es de util-linux y no viene por defecto en Termux: si no está, alcanza con nohup
S=$(command -v setsid || true)
$S nohup proot-distro login debian -- node /root/.pixel/bridge.js \
  >> "$HOME/.pixel-bridge.out" 2>&1 < /dev/null &
echo $! > "$PID"
