# Instalación del entorno de la pestaña TERMINAL. Lo manda el launcher a una sesión visible de Termux:
#   bash -c "<este archivo>" setup "<token>" [--toolchain]
# Se puede volver a correr: cada paso saltea lo que ya está.
set -e
# Cada toque en INSTALAR abre otra sesión de Termux: dos corridas a la vez se pisan el lock de apt
L=$PREFIX/tmp/pixel-setup.pid
if [ -f "$L" ] && kill -0 "$(cat "$L")" 2>/dev/null; then
  echo 'Ya hay una instalación corriendo en otra sesión de Termux: deslizá desde el borde izquierdo y elegila.'
  exit 1
fi
mkdir -p "$PREFIX/tmp" && echo $$ > "$L"
echo '== Pixel Launcher: instalando el entorno de Claude =='
yes | pkg update -y
pkg update -y # después del upgrade hay que releer los índices o no encuentra proot-distro
pkg install -y proot-distro termux-api
# /sdcard dentro de Debian (los APKs para instalar pasan por ahí): Android pregunta una vez
[ -d ~/storage ] || termux-setup-storage
# proot-distro 5.x guarda el rootfs en containers/debian/rootfs (antes installed-rootfs/debian) y `list` escribe a stderr:
# no dependemos de esa ruta, todo entra por login
proot-distro login debian -- true >/dev/null 2>&1 || proot-distro install debian
printf '%s\n' "$1" | proot-distro login debian -- sh -c 'umask 077; mkdir -p /root/.pixel; cat > /root/.pixel/token'

in_debian() { proot-distro login debian -- bash -lc "$1"; }

in_debian '
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y nodejs git curl ca-certificates ripgrep unzip xz-utils
command -v claude >/dev/null || [ -x ~/.local/bin/claude ] || curl -fsSL https://claude.ai/install.sh | bash
# el puente y "claude" sin login shell no ven ~/.local/bin
ln -sf ~/.local/bin/claude /usr/local/bin/claude
claude --version
'

# Misma keystore que la PC: los builds del teléfono se instalan encima (adb push a /sdcard/Download/).
if [ -f /sdcard/Download/debug.keystore ]; then
  in_debian 'mkdir -p ~/.android && cp /sdcard/Download/debug.keystore ~/.android/'
  echo 'keystore de la PC copiada'
fi

if [ "$2" = --toolchain ]; then
  echo '== toolchain: JDK, Android SDK y Flutter =='
  # En arm64 sale solo `flutter build apk --debug`: no hay gen_snapshot linux-arm64 para release.
  in_debian "$(cat <<'EOF'
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get install -y openjdk-21-jdk-headless zip libglu1-mesa || apt-get install -y openjdk-17-jdk-headless zip libglu1-mesa
# misma versión que la PC (Dart 3.9): baja solo su Dart linux-arm64
[ -d ~/flutter ] || git clone --depth 1 -b 3.35.5 https://github.com/flutter/flutter ~/flutter
ln -sf ~/flutter/bin/flutter /usr/local/bin/flutter
ln -sf ~/flutter/bin/dart /usr/local/bin/dart
SDK=~/android-sdk
# Fijo en 15641748: desde 16111833 sdkmanager delega en bin/android, un binario x86_64 que no corre en arm64
if [ ! -x $SDK/cmdline-tools/latest/bin/sdkmanager ] || [ -e $SDK/cmdline-tools/latest/bin/android ]; then
  curl -fsSLo /tmp/clt.zip https://dl.google.com/android/repository/commandlinetools-linux-15641748_latest.zip
  mkdir -p $SDK/cmdline-tools && unzip -qo /tmp/clt.zip -d $SDK/cmdline-tools && rm /tmp/clt.zip
  rm -rf $SDK/cmdline-tools/latest && mv $SDK/cmdline-tools/cmdline-tools $SDK/cmdline-tools/latest
fi
yes | $SDK/cmdline-tools/latest/bin/sdkmanager --licenses >/dev/null
$SDK/cmdline-tools/latest/bin/sdkmanager 'platforms;android-36' 'build-tools;36.0.0'
# aapt2 de Google para linux-arm64 (estático): el de build-tools es x86
V=9.5.1-16666295
# trae su propio loader (lib64/libc_musl.so, lo busca en $ORIGIN/lib64): sin él, "unable to find loader"
if [ ! -x ~/aapt2/aapt2 ] || [ ! -f ~/aapt2/lib64/libc_musl.so ]; then
  curl -fsSLo /tmp/aapt2.jar https://dl.google.com/dl/android/maven2/com/android/tools/build/aapt2/$V/aapt2-$V-linux_arm64.jar
  mkdir -p ~/aapt2 && unzip -qo /tmp/aapt2.jar aapt2 'lib64/*' -d ~/aapt2 && chmod +x ~/aapt2/aapt2 && rm /tmp/aapt2.jar
fi
# ~/.gradle le gana al gradle.properties del proyecto (que pide 8 GB de heap)
mkdir -p ~/.gradle
cat > ~/.gradle/gradle.properties <<P
android.aapt2FromMavenOverride=$HOME/aapt2/aapt2
org.gradle.jvmargs=-Xmx3g -XX:MaxMetaspaceSize=1g
org.gradle.workers.max=2
pixel.noNdk=true
P
# el NDK de Google es x86_64: sin él, AGP avisa y empaqueta las .so sin pelar (ver android/app/build.gradle.kts)
rm -rf $SDK/ndk
flutter config --no-analytics --android-sdk $SDK
flutter precache --android
flutter --version
EOF
)"
fi

echo
echo 'Listo. Falta el login: en el launcher, TERMINAL → LOGIN (o acá: proot-distro login debian -- claude).'
