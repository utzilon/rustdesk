"""Pone la marca de Utzil Remote sobre RustDesk antes de compilar.

La llama build.py al arrancar, así que corre dentro del workflow de upstream
(Flutter Tag Build) sin tocar .github/. Se puede correr sola desde la raíz del
repo, con el submódulo libs/hbb_common ya bajado: python utzil/marca.py

- Nombre «Utzil Remote» (APP_NAME: ventana, servicio, carpeta y exe instalados).
- Servidor y llave fijos (RENDEZVOUS_SERVER y RS_PUB_KEY, abajo). La 1.5.0 ya no
  los lee de variables al compilar: son constantes de hbb_common/src/config.rs.
- Metadatos del exe (Utzil Think).
- Android: nombre y ícono del launcher. Lo llama flutter/ndk_arm64.sh, porque el
  job de Android no pasa por build.py.
- Íconos: salen de res/utzil-remote/ (utzil-remote.ico, utzil-remote.svg y
  png/utzil-remote-<px>.png, copia de Empresa\\Productos\\Utzil Remote\\icono). Para
  cambiar el ícono basta con reemplazar esos archivos y volver a correr el workflow.

Si ya se aplicó, no hace nada. Si un texto que se reemplaza ya no está (otra
versión de RustDesk), truena: más vale no compilar que compilar a medias con la
marca vieja.
"""

import shutil
import sys
from pathlib import Path

NOMBRE = "Utzil Remote"
EMPRESA = "Utzil Think"
DESCRIPCION = "Utzil Remote - soporte a distancia de Utzil Think"
RENDEZVOUS_SERVER = "212.227.240.121"
RS_PUB_KEY = "gM6BxGwVwshb6CIjHzqsD+fqSBuhvLxzEwuHn5lyaFM="
ICONOS = "res/utzil-remote"
DERECHOS = "Utzil Think. Basado en RustDesk (AGPL-3.0): github.com/utzilon/rustdesk"


def cambiar(ruta, pares):
    p = Path(ruta)
    texto = p.read_bytes().decode("utf-8")  # bytes: sin tocar los fines de línea
    for viejo, nuevo in pares:
        if nuevo in texto:
            continue
        if viejo not in texto:
            sys.exit(f"!! no encontré en {ruta}: {viejo}")
        texto = texto.replace(viejo, nuevo)
    p.write_bytes(texto.encode("utf-8"))
    print(f"marca: {ruta}")


def servidor():
    rs, llave = RENDEZVOUS_SERVER, RS_PUB_KEY
    cambiar("libs/hbb_common/src/config.rs", [
        ('APP_NAME: RwLock<String> = RwLock::new("RustDesk".to_owned())',
         f'APP_NAME: RwLock<String> = RwLock::new("{NOMBRE}".to_owned())'),
        ('pub const RENDEZVOUS_SERVERS: &[&str] = &["rs-ny.rustdesk.com"];',
         f'pub const RENDEZVOUS_SERVERS: &[&str] = &["{rs}"];'),
        ('pub const RS_PUB_KEY: &str = "OeVuKk5nlHiXp+APNn0Y3pC1Iwpwn44JGqrQCsWqmBw=";',
         f'pub const RS_PUB_KEY: &str = "{llave}";'),
    ])


def metadatos():
    winres_viejo = [
        ('LegalCopyright = "Copyright © 2026 Purslane Tech Pte. Ltd. All rights reserved."',
         f'LegalCopyright = "{DERECHOS}"\nCompanyName = "{EMPRESA}"'),
        ('ProductName = "RustDesk"', f'ProductName = "{NOMBRE}"'),
        ('FileDescription = "RustDesk Remote Desktop"', f'FileDescription = "{DESCRIPCION}"'),
    ]
    cambiar("Cargo.toml", winres_viejo)
    cambiar("libs/portable/Cargo.toml", winres_viejo)
    cambiar("flutter/windows/runner/Runner.rc", [
        ('VALUE "CompanyName", "Purslane Tech Pte. Ltd."', f'VALUE "CompanyName", "{EMPRESA}"'),
        ('VALUE "FileDescription", "RustDesk Remote Desktop"', f'VALUE "FileDescription", "{DESCRIPCION}"'),
        ('VALUE "LegalCopyright", "Copyright © 2026 Purslane Tech Pte. Ltd. All rights reserved."',
         f'VALUE "LegalCopyright", "{DERECHOS}"'),
        ('VALUE "ProductName", "RustDesk"', f'VALUE "ProductName", "{NOMBRE}"'),
    ])
    # El nombre con que se busca la ventana ya abierta antes de que cargue la DLL.
    cambiar("flutter/windows/runner/main.cpp", [
        ('std::wstring app_name = L"RustDesk";', f'std::wstring app_name = L"{NOMBRE}";'),
    ])


def iconos():
    # Se copian tal cual: el .ico trae 16, 24 y 32 px dibujados a mano y no se
    # regenera desde el PNG grande.
    def copiar(fuente, destino):
        shutil.copyfile(f"{ICONOS}/{fuente}", destino)
        print(f"ícono: {destino}")

    copiar("utzil-remote.ico", "res/icon.ico")  # exe de Rust y el portable
    copiar("utzil-remote.ico", "flutter/windows/runner/resources/app_icon.ico")  # exe de la app
    copiar("utzil-remote.ico", "res/tray-icon.ico")  # bandeja
    copiar("png/utzil-remote-1024.png", "res/icon.png")
    copiar("png/utzil-remote-32.png", "res/32x32.png")
    copiar("png/utzil-remote-64.png", "res/64x64.png")
    copiar("png/utzil-remote-128.png", "res/128x128.png")
    copiar("png/utzil-remote-256.png", "res/128x128@2x.png")
    copiar("png/utzil-remote-1024.png", "res/mac-icon.png")
    # La app pinta assets/icon.png y solo si no está cae a assets/icon.svg.
    copiar("png/utzil-remote-512.png", "flutter/assets/icon.png")
    copiar("utzil-remote.svg", "flutter/assets/icon.svg")


def android():
    res = "flutter/android/app/src/main/res"
    cambiar("flutter/android/app/src/main/AndroidManifest.xml", [
        ('android:label="RustDesk"', f'android:label="{NOMBRE}"'),
        ('android:label="RustDesk Input"', f'android:label="{NOMBRE} Input"'),
    ])
    cambiar(f"{res}/values/strings.xml", [
        ('<string name="app_name">RustDesk</string>', f'<string name="app_name">{NOMBRE}</string>'),
    ])
    # El ícono adaptativo de RustDesk (Android 8+) le gana a los png: se quita
    # para que el launcher use el de la diseñadora. Por densidad va el png de
    # ella que más se acerca hacia arriba; Android lo escala al dibujarlo.
    for xml in ("ic_launcher.xml", "ic_launcher_round.xml"):
        Path(f"{res}/mipmap-anydpi-v26/{xml}").unlink(missing_ok=True)
    for densidad, px in (("mdpi", 48), ("hdpi", 128), ("xhdpi", 128), ("xxhdpi", 256), ("xxxhdpi", 256)):
        for nombre in ("ic_launcher.png", "ic_launcher_round.png"):
            shutil.copyfile(f"{ICONOS}/png/utzil-remote-{px}.png", f"{res}/mipmap-{densidad}/{nombre}")
    print("marca: android")


def aplicar():
    servidor()
    metadatos()
    iconos()
    android()


if __name__ == "__main__":
    aplicar()
