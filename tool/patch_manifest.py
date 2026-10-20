"""Añade permisos de almacenamiento y el nombre de la app al AndroidManifest generado."""
import re
import pathlib

path = pathlib.Path("android/app/src/main/AndroidManifest.xml")
s = path.read_text(encoding="utf-8")

perms = (
    '    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>\n'
    '    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"/>\n'
    '    <uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE"/>\n'
)
if "MANAGE_EXTERNAL_STORAGE" not in s:
    s = s.replace("<application", perms + "    <application", 1)
    s = s.replace("<application", '<application android:requestLegacyExternalStorage="true"', 1)
s = re.sub(r'android:label="[^"]*"', 'android:label="Gestor de Libros"', s, count=1)
path.write_text(s, encoding="utf-8")
print("Manifest parcheado")
