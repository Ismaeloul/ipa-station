# Genera una clave de cifrado de 32 bytes en hexadecimal para JAS_SECRET_KEY.
#
#   powershell -ExecutionPolicy Bypass -File scripts\gen-secret.ps1
#
# Solo hace falta si quieres fijar la clave tu mismo. Si no la pones, el
# contenedor genera una en el primer arranque y la guarda en data/secret.key,
# que es igual de valido.
#
# Copia el resultado a la variable JAS_SECRET_KEY del fichero .env.
# Si la cambias despues de haber iniciado sesion con el Apple ID, los tokens
# guardados dejan de descifrarse y hay que volver a anadir la cuenta.

$bytes = New-Object byte[] 32
[System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
($bytes | ForEach-Object { $_.ToString('x2') }) -join ''
