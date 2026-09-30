# app_vps

Aplicación personal Flutter Material 3 para administrar VPS de Clouding. Se mantiene el proyecto, nombre y plataformas existentes. No contiene credenciales ni servidores de demostración.

## Ejecutar

```sh
flutter pub get
flutter run -d chrome
flutter run -d <dispositivo-android>
flutter analyze
flutter test
flutter build web
flutter build apk --debug
```

Android requiere API 23 o superior. La compilación release conserva la configuración de firma del proyecto original; configura tu propia firma antes de distribuir una APK.

En Configuración, introduce la API KEY y pulsa **Validar y guardar**. La validación realiza solo consultas; no modifica servidores. Una clave Operator sirve para operaciones básicas; cambiar nombres requiere Administrator. Read-only permite consultar.

## Funciones

- Dashboard paginado completo: búsqueda por nombre/IP, filtros, estados y capacidad asignada de CPU/RAM/SSD. IP obtenidas de publicPorts y vpcPorts, con respaldo en campos antiguos.
- Encender, apagar, reiniciar, archivar, desarchivar y renombrar, siempre con confirmación. Los estados transitorios y las operaciones pendientes bloquean nuevos envíos.
- Detalles del servidor, sistema, DNS, creación, backups y snapshots. Costes obtenidos de `cost.pricePerHour` y `cost.pricePerMonthApprox` mediante la consulta de detalles. **Consultar costes actuales** recupera los detalles secuencialmente; si se alcanza el límite de API se muestran los importes recuperados y el error. El subtotal indica cuántos servidores tienen costes conocidos. No es una factura; el importe mensual es una aproximación de Clouding.
- No se inventa uso de CPU, RAM, disco, transferencia, facturación ni ahorro: el contrato consultado no ofrece esas métricas. Los precios de Clouding se presentan en euros.
- Archivado semanal por servidor con selección de días y hora, pausa y eliminación. Para modificar días/horario, elimina la programación y crea otra.
- Temas claro, oscuro y del sistema; navegación adaptable a móvil y escritorio.
- Progreso real mediante acciones de Clouding, consultadas cada 15 segundos. Actividad reciente local (últimos 50 eventos, en memoria).

## API verificada

Fuente oficial: https://api.clouding.io/docs/ y su especificación https://api.clouding.io/docs/clouding-io-openapi-v1.yaml (consultada el 30/09/2026).

Base fija `https://api.clouding.io/v1`, autenticación `X-API-KEY`:

| Método | Ruta | Contrato utilizado |
| --- | --- | --- |
| GET | /servers?page=N&pageSize=200 | servers, links.next, meta; todas las páginas |
| GET | /servers/{id} | ServerDetailed, incluidos cost y puertos |
| POST | /servers/{id}/start | UserAction |
| POST | /servers/{id}/stop | UserAction |
| POST | /servers/{id}/reboot | UserAction |
| POST | /servers/{id}/archive | UserAction |
| POST | /servers/{id}/unarchive | UserAction |
| PATCH | /servers/{id}/rename | {"newServerName": "..."} |
| GET | /actions/{id} | pending / inProgress / completed / errored |

Las peticiones tienen límite de tiempo de 30 segundos. No hay reintentos automáticos de escrituras. Los bloqueos se guardan antes de enviar y sobreviven a reinicios. Un resultado incierto muestra **Actualizar y revisar**: se consulta el listado y se desbloquea con confirmación, para que compruebes el resultado antes de repetir. Las acciones con ID siguen consultándose hasta un estado terminal. Los errores de permisos, autenticación, cuota, red y respuestas inválidas se muestran sin registrar la clave.

## Seguridad y Web

Android: `flutter_secure_storage`, cifrado y Android Keystore; se deshabilita el backup de la aplicación para evitar restaurar claves cifradas sin su clave de dispositivo. Permiso INTERNET en el manifest principal; tráfico HTTPS.

Web: la clave se guarda en el almacenamiento local del navegador y se recupera automáticamente al recargar o abrir la aplicación. **Eliminar clave** borra también la copia persistente. Una conexión directa no puede mantenerla secreta frente al navegador, extensiones o scripts del mismo origen. Se guarda mediante SharedPreferences (localStorage en Web), sin cifrado secreto frente al navegador; no se incluye en el código ni en la URL. Borrar los datos del sitio también elimina la clave. Preferencias, horarios y bloqueos sí se guardan localmente; se usa una huella SHA-256 de la clave para asociarlos y evitar aplicar horarios a otra cuenta. Cambiar de clave o eliminarla borra las programaciones.

Se verificaron preflight OPTIONS sin credenciales desde `http://localhost:8080`: GET /servers , POST /servers/cors-check/archive y PATCH /servers/cors-check/rename devolvieron 204, `Access-Control-Allow-Origin: *`, el método solicitado y los encabezados x-api-key/content-type. No se envió el POST. Esto verifica la política de preflight en ese origen y momento, no una operación autenticada. Usa HTTPS en producción. Si Clouding modifica CORS, el navegador puede bloquear la conexión y hará falta un servicio intermedio bajo tu control que mantenga la clave fuera del cliente. No desactives la seguridad del navegador.

## Programaciones y ejecución permanente

Las programaciones se ejecutan únicamente con la aplicación abierta, activa y con una clave conectada. Se comprueba cada 15 segundos, dentro del minuto elegido, en la zona horaria local del dispositivo. Cambiar de zona horaria cambia la hora efectiva. Android en segundo plano y las pestañas suspendidas no garantizan ejecución. No hay notificaciones, servicio Android en segundo plano ni recuperación de horarios perdidos.

Guardar o reactivar una programación es la confirmación que autoriza sus futuros archivados. Cada ocurrencia se marca y guarda antes de consultar/enviar. Un servidor ya archivado se omite; si está cambiando de estado o tiene otra operación, se registra la omisión. Los fallos no se reintentan en la misma fecha. Consulta Actividad reciente para revisar los resultados. No ejecutes dos instancias con la misma programación: el bloqueo es local, no distribuido.

Para funcionamiento permanente, configura un servicio externo en una máquina siempre encendida (preferiblemente distinta del VPS que se archivará):

1. Guarda la API KEY en un gestor de secretos o archivo protegido que solo pueda leer el usuario del servicio. Nunca la pongas en el repositorio, URL, historial ni logs.
2. Usa cron o un temporizador systemd con días y hora explícitos, indicando la zona horaria. Por ejemplo `30 22 * * 1,3,5` significa lunes, miércoles y viernes a las 22:30 en la zona horaria del servicio.
3. Un trabajador consulta GET /servers/{id}, omite Archived y estados transitorios, registra una ocurrencia única (servidor + fecha + horario) y envía POST /servers/{id}/archive con X-API-KEY.
4. Guarda el ID de acción y consulta GET /actions/{id} hasta completed/errored. Implementa un bloqueo exclusivo y estado duradero antes de enviar; ante timeout, concilia la acción/estado en vez de reenviar ciegamente. Respeta las cuotas y registra fallos sin la clave.
5. Pausa/elimina la programación equivalente en la app para evitar dos ejecutores.

Las programaciones locales no se sincronizan con ese servicio: hay que configurar allí sus horarios. La aplicación no instala ni ejecuta ningún servicio externo ni operación real durante desarrollo/pruebas.

## Estructura

- `lib/main.dart`: arranque.
- `lib/src/api.dart`: cliente REST, autenticación y paginación.
- `lib/src/models.dart`: servidor y programación.
- `lib/src/controller.dart`: estado, almacenamiento, operaciones y planificador.
- `lib/src/app.dart`: temas, dashboard, costes, horarios y configuración.
- `test/`: contratos HTTP con respuestas de prueba, horarios y UI adaptable; sin acceso a VPS reales.
