# Atajos de desarrollo. Uso: .\dev.ps1 <comando>
param([string]$cmd = 'help')
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
$pkg = 'com.adrip.pixel_launcher'
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) { $env:Path = "C:\src\flutter\bin;$env:Path" }

# La ventana del emulador abre fuera de pantalla en este monitor: la trae arriba a la izquierda.
function Show-Emulator {
  Add-Type -Namespace Win -Name U -MemberDefinition '
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
    [DllImport("user32.dll")] public static extern IntPtr FindWindow(string c, string t);'
  $main = (Get-Process qemu-system-x86_64 -ErrorAction SilentlyContinue | Where-Object MainWindowTitle -like 'Android Emulator*').MainWindowHandle
  if (-not $main) { return 'no hay ventana del emulador' }
  [void][Win.U]::SetWindowPos($main, [IntPtr]::Zero, 20, 0, 0, 0, 5)        # 5 = sin cambiar tamaño ni orden
  $bar = [Win.U]::FindWindow($null, 'Emulator')                             # la barra lateral de botones
  if ($bar -ne [IntPtr]::Zero) { [void][Win.U]::SetWindowPos($bar, [IntPtr]::Zero, 304, 31, 0, 0, 5) }
  'ventana del emulador en pantalla'
}

switch ($cmd) {
  'emu'     {
    flutter emulators --launch pixel7 --cold   # sin snapshot: restaurarlo deja la app con un frame viejo congelado
    & $adb wait-for-device; Start-Sleep 5   # ponytail: espera fija a que la ventana termine de ubicarse
    Show-Emulator
  }
  'win'     { Show-Emulator }
  'run'     { flutter run }                                  # hot reload: r / R
  'test'    { flutter analyze; flutter test }
  'apk'     { flutter build apk --release }                  # build\app\outputs\flutter-apk\app-release.apk
  'install' { flutter build apk --release; & $adb install -r build\app\outputs\flutter-apk\app-release.apk }
  'home'    { & $adb shell cmd package set-home-activity "$pkg/.MainActivity"; & $adb shell input keyevent KEYCODE_HOME }
  'shot'    { & $adb exec-out screencap -p > shot.png; "shot.png" }   # PowerShell 7 conserva los bytes; en 5.1 usá Bash
  'logs'    { & $adb logcat -s flutter }
  'devices' { & $adb devices }
  default   { 'comandos: emu | win | run | test | apk | install | home | shot | logs | devices' }
}
