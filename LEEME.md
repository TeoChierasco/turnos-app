# Turnos online

Sistema de turnos para varios comercios con un solo proyecto. Costo para arrancar: **$0 por mes**.

| Pieza | Servicio | Costo |
|---|---|---|
| Base de datos + login | Supabase (plan Free) | $0 |
| Hosting de las páginas | Cloudflare Pages (plan Free) | $0 |
| Recordatorios | Links de WhatsApp (`wa.me`) que manda el comercio con un toque | $0 |
| Dominio propio (opcional) | .com.ar en NIC Argentina | pago anual chico |

---

## Qué hace

### Para el cliente (`/?n=slug-del-local`)
- Elige servicio, día y horario. Solo ve los horarios realmente libres, respetando la duración de cada servicio.
- Ve el aviso del comercio (por ejemplo "Solo efectivo") y los horarios de atención.
- Al confirmar puede avisar por WhatsApp, agregar el turno a Google Calendar o al calendario del celular (con alarma 2 horas antes) y copiar su link para cancelar.
- **Puede cancelar solo** desde su link, hasta el límite que fije el comercio. Eso libera el horario para otro cliente.
- El navegador recuerda su nombre y teléfono, y le muestra sus próximos turnos.

### Para el comercio (`/admin.html`)
- **Agenda:** navega por día y muestra los turnos, lo cobrado y los horarios libres. Se actualiza en tiempo real.
  - **+ Turno:** carga a alguien que llamó o vino sin turno.
  - **Recordar:** abre WhatsApp con el recordatorio escrito. Es gratis.
  - **Asistió / No vino / Cancelar / Deshacer.**
  - **Bloquear:** cierra un horario suelto. **Bloquear lo que queda libre** cierra el día entero (feriados, vacaciones) sin tocar los turnos que ya había.
- **Resumen del mes:** muestra atendidos, facturado, lo que está por venir, el porcentaje de ausencias, los servicios más pedidos, los días con más movimiento y los clientes frecuentes.
  - **Para recuperar:** lista a los clientes que no vienen hace más de 30 días, con un botón para escribirles por WhatsApp. Es una herramienta de venta muy fuerte para el comercio.
  - **Descargar planilla (CSV):** se abre en Excel o Google Sheets.
- **Ajustes:**
  - Datos del local, color de la marca y aviso para clientes.
  - Reglas de reserva: cada cuánto empiezan los turnos, la anticipación mínima, hasta cuándo se puede cancelar y cuántos días hacia adelante se puede reservar.
  - Horarios por día, con hasta 3 franjas (por ejemplo, mañana y tarde).
  - Servicios: nombre, descripción, duración, precio, orden y activo o inactivo.
  - **Cartel con QR** para imprimir y pegar en el mostrador.
- **App en el celular:** desde Chrome, "Agregar a la pantalla principal" lo instala como una app.
- **Recuperar contraseña** por mail.

### Fila virtual (locales por orden de llegada)
- **Modo de atención:** en **Ajustes → Cómo atendés**, cada comercio elige **Con turnos**, **Por orden de llegada** o **Las dos cosas** (por ejemplo, turnos en la semana y fila los sábados). "Las dos cosas" está disponible desde el plan Equipo.
- **El cliente:**
  - Entra al mismo link, ve cuántas personas hay esperando y cuánto va a tardar.
  - Se anota con nombre y WhatsApp.
  - En su página ve su número y cuántos tiene adelante, y se actualiza sola.
  - Puede pedir un aviso en el celular cuando le falte poco, salir de la fila o escribirle al local.
  - Si el local tiene varios barberos, elige con quién o "el primero que se libere".
- **El barbero:** en la pestaña **Fila** elige quién es y toca **"Llamar al siguiente"**. Dos barberos tocando a la vez nunca se llevan a la misma persona. Además tiene:
  - **Avisar:** WhatsApp con el mensaje "te faltan 2" ya escrito, gratis.
  - **+ Anotar:** para el que entra caminando.
  - **Quitar** y **No vino.**
  - **Pausar la fila.**
- **Automático:**
  - La fila se abre y se cierra según los horarios y deja de anotar X minutos antes del cierre.
  - Tiene un máximo de personas esperando y no deja anotarse dos veces con el mismo teléfono.
  - Arranca de cero cada día.
  - **La espera estimada aprende sola:** después de 5 atenciones usa el tiempo real de cada corte.
- **Resumen del mes:**
  - Muestra cuántos se atendieron por fila, la espera promedio, el tiempo por persona y cuántos se fueron.
  - Los clientes de la fila también cuentan para "Clientes frecuentes" y "Para recuperar".
- **Pantalla del local (extra):** `pantalla.html?n=slug` en una tele o tablet.
  - Muestra a quién se atiende y quiénes siguen, solo con el número y el nombre de pila, nunca teléfonos.
  - Incluye un QR para anotarse.
  - La habilitás vos con una línea de SQL (abajo).

### Varios profesionales (opcional)
- En **Ajustes → Profesionales** se carga a cada uno con los días que trabaja.
- El cliente elige con quién o toca **"Cualquiera"**. En ese caso el sistema asigna al profesional libre con menos turnos ese día, para repartir el trabajo de forma pareja.
- En la agenda, cada profesional tiene su pestaña con la cantidad de turnos del día.
- "Bloquear lo que queda libre" cierra el día para todos.
- El resumen del mes muestra cuánto atendió y facturó cada uno.
- Si no se carga ningún profesional, funciona como antes, con una sola agenda.

### Seña con Mercado Pago (opcional)
- En **Ajustes → Seña con Mercado Pago**, el comercio pone el monto y su Access Token.
- **Token:** queda guardado en secreto; ni el propio dueño lo puede volver a ver.
- **Reserva:** el turno queda **15 minutos esperando el pago**. Si no paga, se libera solo para otro cliente.
- **Confirmación:** cuando Mercado Pago avisa que el pago fue aprobado, el turno se confirma automáticamente. El sistema verifica el pago consultando a Mercado Pago, así que no se puede falsificar.
- **Panel:** la agenda muestra "Esperando seña" o "Seña $X" y cuánto resta cobrar.
- **Pagos tardíos:** si alguien paga después de que venció su turno y el horario ya se ocupó, aparece un **aviso en la agenda** para devolverle la plata o reprogramarlo.
- **Costo:** Mercado Pago no tiene costo fijo, cobra su comisión por cada pago.

### Planes (lo que ve y usa cada comercio)
| Función | Agenda | Equipo | Full con seña |
| --- | --- | --- | --- |
| Profesionales activos | 1 | hasta 5 | sin límite |
| Color propio y aviso para clientes | no | sí | sí |
| Clientes frecuentes y «Para recuperar» | no | sí | sí |
| Seña con Mercado Pago | no | no | sí |
| Turnos **o** fila | sí | sí | sí |
| Turnos **y** fila a la vez | no | sí | sí |

- **Qué ve el comercio:** las funciones que no incluye su plan aparecen con un aviso y un botón **«Mejorar plan»** que te escribe a tu WhatsApp. Tu número va en `SOPORTE_WHATSAPP`, dentro de `config.js`.
- **Límites en el servidor:** el máximo de profesionales y la seña se controlan en la base de datos, así que no se pueden saltear desde el navegador.
- **Bajada de plan:** si un comercio baja de plan, siguen atendiendo solo los primeros profesionales según su orden.

### Seguridad
- Los nombres y teléfonos solo los ve el dueño de cada comercio. Un comercio no ve los datos de otro.
- La base de datos impide turnos superpuestos aunque dos personas reserven en el mismo instante.
- Valida horarios, anticipación y días máximos del lado del servidor, así que no se puede saltear desde el navegador.
- Anti-spam: se permiten como máximo 3 turnos futuros por teléfono en cada comercio.
- El comercio no puede reactivarse solo si vos lo pausás.

---

## Puesta en marcha (unos 20 minutos)

1. **Supabase:** creá una cuenta en supabase.com y un proyecto nuevo (región São Paulo).
2. **Tu WhatsApp:** en `config.js`, poné tu número en `SOPORTE_WHATSAPP`.
3. **Base de datos:** en *SQL Editor*, pegá todo `schema.sql` y tocá *Run*.
4. **Usuario del comercio:** en *Authentication > Users > Add user*, creá el usuario del dueño con email y contraseña. Marcá *Auto confirm user*.
5. **Alta del comercio:** editá `alta-negocio.sql` (email del dueño, slug, nombre, WhatsApp, plan y servicios) y corrélo. Lo demás lo puede cambiar el dueño desde Ajustes.
6. **Configuración:** en *Project Settings > API*, copiá la *Project URL* y la *anon public key* a `config.js`.
7. **Recuperación de contraseña:** en *Authentication > URL Configuration*, poné tu dominio en *Site URL* (por ejemplo `https://tu-sitio.pages.dev`) y agregá `https://tu-sitio.pages.dev/admin.html` en *Redirect URLs*.
8. **Publicación:** en Cloudflare, andá a *Workers & Pages > Create > Pages > Upload assets* y arrastrá esta carpeta.
9. **Mercado Pago (solo si algún comercio va a pedir seña):** subí las dos funciones de la carpeta `supabase/functions`. Desde la terminal, con la [CLI de Supabase](https://supabase.com/docs/guides/cli):
   ```
   supabase login
   supabase link --project-ref TU-PROYECTO
   supabase functions deploy crear-pago
   supabase functions deploy mp-webhook --no-verify-jwt
   ```
   La opción `--no-verify-jwt` es necesaria porque quien llama a `mp-webhook` es Mercado Pago, que no tiene sesión en tu sistema. También se pueden crear desde el panel de Supabase (*Edge Functions → Deploy a new function*), pegando el código y desactivando la verificación JWT en `mp-webhook`.
10. **Links finales:**
   - Clientes: `https://tu-sitio.pages.dev/?n=barberia-del-canal`
   - Dueño: `https://tu-sitio.pages.dev/admin.html`
   - Pantalla del local (si la habilitaste): `https://tu-sitio.pages.dev/pantalla.html?n=barberia-del-canal`

### Actualizaciones
`schema.sql` se puede volver a correr sin perder datos. Cuando cambie, pegalo de nuevo y tocá *Run*.

---

## Tareas tuyas como dueño del sistema (SQL Editor)

```sql
-- Ver todos tus comercios
select slug, nombre, activo, created_at from negocios order by created_at;

-- Pausar un comercio que no pagó (sus clientes no pueden reservar; él ve un aviso)
update negocios set activo = false where slug = 'barberia-del-canal';

-- Reactivarlo
update negocios set activo = true where slug = 'barberia-del-canal';

-- Cambiar de plan (agenda | equipo | full)
update negocios set plan = 'equipo' where slug = 'barberia-del-canal';

-- Habilitar o quitar la pantalla del local (extra)
update negocios set pantalla = true where slug = 'barberia-del-canal';

-- Si bajás a plan 'agenda' un comercio que usa turnos y fila a la vez, cambiá también el modo:
update negocios set plan = 'agenda', modo = 'fila' where slug = 'barberia-del-canal';

-- Ver qué plan tiene cada uno
select slug, nombre, plan, activo from negocios order by plan;

-- Turnos por comercio en el último mes (para ver quién lo usa más)
select n.nombre, count(*) from turnos t join negocios n on n.id = t.negocio_id
where t.inicio > now() - interval '30 days' and t.estado <> 'bloqueado'
group by 1 order by 2 desc;
```

---

## Cosas a saber

- **Pausa del plan Free:** Supabase pausa los proyectos gratuitos que pasan una semana sin actividad. Con comercios usándolo a diario no pasa. Cuando tengas varios clientes pagando, el plan Pro cuesta USD 25 por mes en total, que se reparte entre todos.
- **Zona horaria:** está pensado para Argentina (UTC-3), que se configura en `config.js` y en la base de datos.
- **Probar la seña sin plata real:** Mercado Pago da credenciales de prueba (empiezan con `TEST-`) y usuarios de prueba. El panel acepta esos tokens.
- **Próximos pasos posibles:**
  - Servicios que hace solo un profesional (hoy todos hacen todos los servicios).
  - Recordatorios automáticos con la API oficial de WhatsApp, que se cobra por mensaje. Conviene ofrecerlo como extra pago.
