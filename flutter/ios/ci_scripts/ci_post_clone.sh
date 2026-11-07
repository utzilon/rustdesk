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
# La librería se toma de la release del commit más cercano hacia atrás que tenga
# una, SOLO si desde ese commit no cambió nada de lo que entra en ella (src, libs,
# Cargo, build.rs, utzil/). Así un arreglo que solo toca lo de Xcode (este script,
# por ejemplo) no obliga a recompilar una hora de Rust. Si cambió algo, o no hay
# ninguna, se para aquí y lo dice: hay que correr utzil-remote-ios.yml sobre el
# commit que se etiqueta.
set -e

RAIZ="${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$(dirname "$0")/../../.." && pwd)}"
COMMIT="${CI_COMMIT:-$(git -C "$RAIZ" rev-parse HEAD)}"
FLUTTER_VERSION="3.24.5"   # la misma de utzil-remote.yml
LIB="utzil-remote-ios-lib.tar.gz"
RELEASES="https://github.com/utzilon/rustdesk/releases/download"
cd "$RAIZ"

echo "--- Librería de Rust para el commit $COMMIT"
BASE=""
for c in $(git rev-list --max-count=30 "$COMMIT" 2>/dev/null || echo "$COMMIT"); do
  if curl -fsSL --retry 2 "$RELEASES/ios-lib-$c/$LIB.sha256" -o "/tmp/$LIB.sha256" 2>/dev/null; then
    BASE="$c"
    break
  fi
done
if [ -z "$BASE" ]; then
  echo "ERROR: ningún commit de los últimos 30 tiene la release ios-lib-<commit>."
  echo "       Corre utzil-remote-ios.yml sobre $COMMIT y vuelve a etiquetar."
  exit 1
fi
if [ "$BASE" != "$COMMIT" ] && ! git diff --quiet "$BASE" "$COMMIT" -- src libs Cargo.toml Cargo.lock build.rs utzil; then
  echo "ERROR: la librería más cercana es la de $BASE, y desde ahí cambió código que entra en ella:"
  git diff --stat "$BASE" "$COMMIT" -- src libs Cargo.toml Cargo.lock build.rs utzil
  echo "       Corre utzil-remote-ios.yml sobre $COMMIT y vuelve a etiquetar."
  exit 1
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
