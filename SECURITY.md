# Seguridad

Si encuentras una vulnerabilidad o una credencial expuesta, evita publicar
tokens, datos personales o instrucciones con acceso a producción en una issue.
Usa el canal privado **Security → Report a vulnerability** si está habilitado
en GitHub, o solicita un canal privado al mantenedor sin adjuntar el secreto.

Incluye el componente, el comportamiento observado y un caso mínimo con datos
ficticios. Este proyecto está en fase de prototipo y no ofrece un plazo de
respuesta garantizado.

## Manejo de credenciales

- Los clientes Flutter y Vite utilizan claves públicas de Supabase.
- `service_role`, conexiones PostgreSQL, secretos OAuth y claves de firma se
  conservan en variables del servidor, archivos locales ignorados o secretos
  de GitHub Actions.
- Los archivos `.env.example` y `*.example.json` contienen marcadores.
- `dart-define` y `VITE_*` se incorporan en los builds públicos; no protegen
  secretos.

Ante una exposición, revocar o rotar primero la credencial. Borrarla del
último commit no la elimina del historial.

Ver [controles de publicación](docs/github-publication.md).
