#!/bin/sh
# Utzil Remote en Xcode Cloud: corre después de clonar y ANTES de compilar.
#
# La librería de Rust NO se compila aquí (card uzKJFFe0, opción B): son ~60 min de
# vcpkg y cargo que en Xcode Cloud irían sin caché y quizá en una Mac Intel sin
# Homebrew. La compila el workflow utzil-remote-ios.yml de GitHub Actions —sin
# firmar, sin llaves— y la deja en la release pública ios-lib-<commit> de
# utzilon/rustdesk. Aquí se baja la que corresponde a este commit (con los
# archivos del bridge de Flutter que van con ella), se pone la marca y se prepara Flutter;
# Xcode Cloud compila la app y la firma con la cuenta del equipo.
#
# Se usa la release de este mismo commit si la hay; si no, la que dice
# libreria-ios.txt, SOLO si la huella de lo que entra en la librería (src, libs,
# Cargo, build.rs, utzil/) es la misma. Así un arreglo que solo toca lo de Xcode
# (este script, por ejemplo) no obliga a recompilar una hora de Rust. Va por
# huella y no por historial porque Xcode Cloud clona sin historial: con
# `git rev-list` solo veía el commit etiquetado (corrida 1, 2026-11-07). Si la
# huella no cuadra, se para aquí y lo dice.
set -e

RAIZ="${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$(dirname "$0")/../../.." && pwd)}"
COMMIT="${CI_COMMIT:-$(git -C "$RAIZ" rev-parse HEAD)}"
FLUTTER_VERSION="3.24.5"   # la misma de utzil-remote.yml
LIB="utzil-remote-ios-lib.tar.gz"
RELEASES="https://github.com/utzilon/rustdesk/releases/download"
cd "$RAIZ"

echo "--- Librería de Rust para el commit $COMMIT"
PIN="$RAIZ/flutter/ios/ci_scripts/libreria-ios.txt"
huella() { # commit → git rev-parse de lo que entra en la librería, en una línea
  for r in src libs Cargo.toml Cargo.lock build.rs utzil; do git rev-parse "$1:$r"; done | tr '\n' ' ' | sed 's/ $//'
}
if curl -fsSL --retry 2 "$RELEASES/ios-lib-$COMMIT/$LIB.sha256" -o "/tmp/$LIB.sha256" 2>/dev/null; then
  BASE="$COMMIT"
else
  BASE="$(sed -n 's/^commit //p' "$PIN")"
  ESPERADA="$(sed -n 's/^huella //p' "$PIN")"
  ACTUAL="$(huella HEAD)"
  if [ -z "$BASE" ] || [ "$ESPERADA" != "$ACTUAL" ]; then
    echo "ERROR: este commit no tiene release propia y su código de librería no es el de libreria-ios.txt ($BASE)."
    echo "       huella esperada: $ESPERADA"
    echo "       huella de aquí:  $ACTUAL"
    echo "       Corre utzil-remote-ios.yml sobre $COMMIT, pon su commit y su huella en libreria-ios.txt y vuelve a etiquetar."
    exit 1
  fi
  if ! curl -fsSL --retry 3 "$RELEASES/ios-lib-$BASE/$LIB.sha256" -o "/tmp/$LIB.sha256"; then
    echo "ERROR: no pude bajar la release ios-lib-$BASE de libreria-ios.txt."
    exit 1
  fi
fi
echo "    de la release ios-lib-$BASE"
curl -fsSL --retry 3 "$RELEASES/ios-lib-$BASE/$LIB" -o "/tmp/$LIB"
(cd /tmp && shasum -a 256 -c "$LIB.sha256")
# Deja target/aarch64-apple-ios/release/liblibrustdesk.a (la ruta que enlaza el
# proyecto) y los archivos del bridge en flutter/lib y flutter/ios/Runner.
tar -xzf "/tmp/$LIB" -C "$RAIZ"
ls -la target/aarch64-apple-ios/release/liblibrustdesk.a

echo "--- Marca"
# La misma que en las demás plataformas: bundle id, equipo, nombre e íconos (ios()).
python3 utzil/marca.py

echo "--- Flutter $FLUTTER_VERSION"
git clone --depth 1 -b "$FLUTTER_VERSION" https://github.com/flutter/flutter.git "$HOME/flutter"
# El mismo parche que aplica utzil-remote.yml a Flutter 3.24.
(cd "$HOME/flutter" && git apply "$RAIZ/.github/patches/flutter_3.24.4_dropdown_menu_enableFilter.diff")
export PATH="$HOME/flutter/bin:$PATH"
flutter --version
flutter precache --ios

cd "$RAIZ/flutter"
flutter pub get

echo "--- Pods"
# CocoaPods viene en la imagen de Xcode Cloud; solo se instala si faltara.
command -v pod >/dev/null 2>&1 || HOMEBREW_NO_AUTO_UPDATE=1 brew install cocoapods
cd ios
pod install

echo "--- Listo para que Xcode Cloud compile y firme"
