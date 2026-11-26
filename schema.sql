-- =========================================================
-- Turnos online · esquema para Supabase (Postgres)
-- Pegar entero en Supabase > SQL Editor > Run
-- Se puede volver a correr sin perder datos (sirve para actualizar).
-- Un solo proyecto sirve a TODOS los comercios (multi-negocio).
-- =========================================================

create extension if not exists btree_gist;

-- ---------- Tablas ----------
create table if not exists negocios (
  id         uuid primary key default gen_random_uuid(),
  slug       text unique not null check (slug ~ '^[a-z0-9-]{3,40}$'),
  nombre     text not null,
  owner      uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table negocios add column if not exists whatsapp        text;           -- 549294XXXXXXX
alter table negocios add column if not exists direccion       text;
alter table negocios add column if not exists mensaje         text;           -- aviso para clientes
-- horarios por día ISO (1=lunes ... 7=domingo): [["09:00","13:00"],["16:00","20:30"]]
alter table negocios add column if not exists horarios jsonb not null default
  '{"1":[["09:00","13:00"],["16:00","20:30"]],"2":[["09:00","13:00"],["16:00","20:30"]],"3":[["09:00","13:00"],["16:00","20:30"]],"4":[["09:00","13:00"],["16:00","20:30"]],"5":[["09:00","13:00"],["16:00","20:30"]],"6":[["09:00","14:00"]]}';
alter table negocios add column if not exists intervalo       int  not null default 30;
alter table negocios add column if not exists anticipacion_min int not null default 30;   -- minutos mínimos antes de reservar
alter table negocios add column if not exists cancelacion_min  int not null default 60;   -- hasta cuántos minutos antes puede cancelar el cliente
alter table negocios add column if not exists dias_reserva    int  not null default 14;   -- cuántos días hacia adelante se ve la agenda
alter table negocios add column if not exists color           text not null default '#b8261d';
alter table negocios add column if not exists activo          boolean not null default true; -- vos lo apagás si el comercio no paga

do $$ begin
  alter table negocios add constraint negocios_rangos check (
    intervalo between 5 and 120 and anticipacion_min between 0 and 10080
    and cancelacion_min between 0 and 10080 and dias_reserva between 1 and 90
    and color ~ '^#[0-9a-fA-F]{6}$');
exception when duplicate_object then null; end $$;

create table if not exists servicios (
  id           uuid primary key default gen_random_uuid(),
  negocio_id   uuid not null references negocios(id) on delete cascade,
  nombre       text not null,
  descripcion  text,
  duracion_min int  not null check (duracion_min between 5 and 480),
  precio       int  not null default 0 check (precio >= 0),
  orden        int  not null default 0,
  activo       boolean not null default true
);

-- Profesionales (opcional). Si un comercio no carga ninguno, funciona con una sola agenda.
create table if not exists profesionales (
  id         uuid primary key default gen_random_uuid(),
  negocio_id uuid not null references negocios(id) on delete cascade,
  nombre     text not null,
  dias       int[],                 -- días ISO que trabaja (1=lunes..7=domingo); null = todos los del local
  orden      int not null default 0,
  activo     boolean not null default true
);

create table if not exists turnos (
  id          uuid primary key default gen_random_uuid(),
  negocio_id  uuid not null references negocios(id) on delete cascade,
  servicio_id uuid references servicios(id) on delete set null,
  inicio      timestamptz not null,
  fin         timestamptz not null,
  nombre      text not null,
  telefono    text,
  estado      text not null default 'reservado',
  created_at  timestamptz not null default now(),
  check (fin > inicio),
  -- Esto es lo que impide que dos personas reserven el mismo horario,
  -- aunque lo intenten en el mismo milisegundo.
  constraint sin_superposicion exclude using gist (
    negocio_id with =, tstzrange(inicio, fin) with &&
  ) where (estado <> 'cancelado')
);
alter table turnos add column if not exists precio  int;                         -- precio al momento de reservar
alter table turnos add column if not exists origen  text not null default 'web'; -- web | local
alter table turnos add column if not exists notas   text;
alter table turnos add column if not exists cancelado_por text;                  -- cliente | comercio
alter table turnos add column if not exists profesional_id uuid references profesionales(id) on delete set null;
alter table turnos add column if not exists sena       int;          -- seña cobrada
alter table turnos add column if not exists expira     timestamptz;  -- vencimiento de un turno pendiente de pago
alter table turnos add column if not exists mp_pago_id text;
alter table turnos drop constraint if exists turnos_estado_check;
alter table turnos add constraint turnos_estado_check
  check (estado in ('reservado','pendiente_pago','completado','ausente','cancelado','bloqueado'));

-- Sin superposición POR PROFESIONAL (o por local si no hay profesionales)
alter table turnos drop constraint if exists sin_superposicion;
alter table turnos add constraint sin_superposicion exclude using gist (
  negocio_id with =,
  (coalesce(profesional_id, '00000000-0000-0000-0000-000000000000'::uuid)) with =,
  tstzrange(inicio, fin) with &&
) where (estado <> 'cancelado');

alter table negocios add column if not exists sena_monto int not null default 0;  -- 0 = sin seña

-- Plan contratado: agenda | equipo | full. Lo cambiás vos; el comercio no puede.
alter table negocios add column if not exists plan text not null default 'agenda';
do $$ begin
  alter table negocios add constraint negocios_plan check (plan in ('agenda','equipo','full'));
exception when duplicate_object then null; end $$;

-- Cuántos profesionales activos permite cada plan
create or replace function limite_profesionales(p_plan text) returns int
language sql immutable as $$
  select case p_plan when 'full' then 1000 when 'equipo' then 5 else 1 end;
$$;

-- Impide pasarse del límite de profesionales del plan
create or replace function _controlar_limite_pros() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.activo and (
    select count(*) from profesionales
    where negocio_id = new.negocio_id and activo and id <> new.id
  ) >= (select limite_profesionales(plan) from negocios where id = new.negocio_id) then
    raise exception 'limite_profesionales';
  end if;
  return new;
end $$;
drop trigger if exists limite_pros on profesionales;
create trigger limite_pros before insert or update of activo, negocio_id on profesionales
  for each row execute function _controlar_limite_pros();

-- Token de Mercado Pago de cada comercio: nadie lo puede leer desde el navegador
create table if not exists negocio_secretos (
  negocio_id      uuid primary key references negocios(id) on delete cascade,
  mp_access_token text,
  updated_at      timestamptz not null default now()
);

create index if not exists turnos_negocio_inicio on turnos (negocio_id, inicio);

-- ---------- Seguridad (Row Level Security) ----------
alter table negocios  enable row level security;
alter table servicios enable row level security;
alter table turnos    enable row level security;
alter table profesionales    enable row level security;
alter table negocio_secretos enable row level security;
revoke all on negocio_secretos from anon, authenticated;   -- solo las funciones del servidor

drop policy if exists profesionales_leer on profesionales;
create policy profesionales_leer on profesionales for select using (true);
drop policy if exists profesionales_dueno on profesionales;
create policy profesionales_dueno on profesionales for all
  using (exists (select 1 from negocios n where n.id = negocio_id and n.owner = auth.uid()))
  with check (exists (select 1 from negocios n where n.id = negocio_id and n.owner = auth.uid()));
grant select on profesionales to anon, authenticated;
grant insert, update, delete on profesionales to authenticated;

drop policy if exists negocios_leer on negocios;
create policy negocios_leer on negocios for select using (activo or owner = auth.uid());
drop policy if exists negocios_dueno on negocios;
create policy negocios_dueno on negocios for update using (owner = auth.uid()) with check (owner = auth.uid());

-- El dueño puede editar sus datos, pero NO el slug, el dueño ni "activo" (eso lo manejás vos)
revoke insert, update, delete on negocios from anon, authenticated;
grant select on negocios to anon, authenticated;
grant update (nombre, whatsapp, direccion, mensaje, horarios, intervalo, anticipacion_min,
              cancelacion_min, dias_reserva, color, sena_monto) on negocios to authenticated;

drop policy if exists servicios_leer on servicios;
create policy servicios_leer on servicios for select using (true);
drop policy if exists servicios_dueno on servicios;
create policy servicios_dueno on servicios for all
  using (exists (select 1 from negocios n where n.id = negocio_id and n.owner = auth.uid()))
  with check (exists (select 1 from negocios n where n.id = negocio_id and n.owner = auth.uid()));
grant select on servicios to anon, authenticated;
grant insert, update, delete on servicios to authenticated;

-- Los turnos (con nombres y teléfonos) SOLO los ve el dueño del negocio.
-- El público reserva y cancela a través de las funciones de abajo.
drop policy if exists turnos_dueno on turnos;
create policy turnos_dueno on turnos for all
  using (exists (select 1 from negocios n where n.id = negocio_id and n.owner = auth.uid()))
  with check (exists (select 1 from negocios n where n.id = negocio_id and n.owner = auth.uid()));
revoke all on turnos from anon;
grant select, insert, update, delete on turnos to authenticated;

-- ---------- Funciones públicas ----------
-- (se borran y recrean para poder cambiar sus parámetros en actualizaciones)
drop function if exists ocupados(text, timestamptz, timestamptz);
drop function if exists reservar(text, uuid, timestamptz, text, text);
drop function if exists reservar(text, uuid, timestamptz, text, text, uuid);
drop function if exists ver_turno(uuid);

-- Libera los turnos que quedaron esperando un pago que nunca llegó
create or replace function _liberar_vencidos(p_negocio uuid) returns void
language sql security definer set search_path = public as $$
  update turnos set estado = 'cancelado', cancelado_por = 'vencido'
  where negocio_id = p_negocio and estado = 'pendiente_pago' and expira < now();
$$;
revoke all on function _liberar_vencidos(uuid) from public, anon, authenticated;

-- Horarios ocupados (sin datos personales) para pintar la grilla
create function ocupados(p_slug text, p_desde timestamptz, p_hasta timestamptz)
returns table (inicio timestamptz, fin timestamptz, profesional_id uuid)
language sql security definer set search_path = public stable as $$
  select t.inicio, t.fin, t.profesional_id
  from turnos t join negocios n on n.id = t.negocio_id
  where n.slug = p_slug and n.activo
    and t.estado <> 'cancelado'
    and not (t.estado = 'pendiente_pago' and t.expira < now())
    and t.fin > p_desde and t.inicio < p_hasta
    and p_hasta - p_desde <= interval '92 days';
$$;

-- Reservar un turno validando todo del lado del servidor.
-- p_profesional null = "cualquiera": se asigna al profesional libre con menos turnos ese día.
create function reservar(
  p_slug text, p_servicio uuid, p_inicio timestamptz, p_nombre text, p_telefono text,
  p_profesional uuid default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_neg    negocios;
  v_srv    servicios;
  v_pro    profesionales;
  v_local  timestamp;
  v_dow    int;
  v_ini    time;
  v_fin    time;
  v_hasta  timestamptz;
  v_id     uuid;
  v_estado text := 'reservado';
  v_expira timestamptz;
begin
  select * into v_neg from negocios where slug = p_slug and activo;
  if not found then raise exception 'negocio_inexistente'; end if;
  perform _liberar_vencidos(v_neg.id);

  select * into v_srv from servicios where id = p_servicio and negocio_id = v_neg.id and activo;
  if not found then raise exception 'servicio_invalido'; end if;

  if length(trim(coalesce(p_nombre,''))) < 2 then raise exception 'nombre_invalido'; end if;
  if length(regexp_replace(coalesce(p_telefono,''), '\D', '', 'g')) < 8 then raise exception 'telefono_invalido'; end if;
  if p_inicio < now() + make_interval(mins => v_neg.anticipacion_min) then raise exception 'horario_pasado'; end if;
  if p_inicio > now() + make_interval(days => v_neg.dias_reserva + 1) then raise exception 'muy_lejos'; end if;

  -- ¿Cae dentro del horario de atención de ese día?
  v_local := p_inicio at time zone 'America/Argentina/Buenos_Aires';
  v_dow   := extract(isodow from v_local)::int;
  v_ini   := v_local::time;
  v_fin   := v_ini + make_interval(mins => v_srv.duracion_min);
  v_hasta := p_inicio + make_interval(mins => v_srv.duracion_min);
  if v_fin < v_ini or not exists (
    select 1 from jsonb_array_elements(coalesce(v_neg.horarios -> v_dow::text, '[]')) b
    where (b->>0)::time <= v_ini and (b->>1)::time >= v_fin
  ) then
    raise exception 'fuera_de_horario';
  end if;

  -- Freno anti-spam: máximo 3 turnos futuros por teléfono en el mismo negocio
  if (select count(*) from turnos
      where negocio_id = v_neg.id and estado in ('reservado','pendiente_pago') and inicio > now()
        and regexp_replace(telefono, '\D', '', 'g') = regexp_replace(p_telefono, '\D', '', 'g')) >= 3 then
    raise exception 'demasiados_turnos';
  end if;

  -- Seña: si el comercio la pide y conectó Mercado Pago, el turno queda 15 minutos esperando el pago
  if v_neg.plan = 'full' and v_neg.sena_monto > 0 and exists (
    select 1 from negocio_secretos s where s.negocio_id = v_neg.id and coalesce(s.mp_access_token,'') <> ''
  ) then
    v_estado := 'pendiente_pago';
    v_expira := now() + interval '15 minutes';
  end if;

  -- Sin profesionales: una sola agenda
  if not exists (select 1 from profesionales where negocio_id = v_neg.id and activo) then
    begin
      insert into turnos (negocio_id, servicio_id, inicio, fin, nombre, telefono, precio, origen, estado, expira)
      values (v_neg.id, v_srv.id, p_inicio, v_hasta, left(trim(p_nombre), 60), left(trim(p_telefono), 30),
              v_srv.precio, 'web', v_estado, v_expira)
      returning id into v_id;
    exception when exclusion_violation then
      raise exception 'ocupado';
    end;
    return v_id;
  end if;

  -- Con profesionales: un bloqueo o turno "de todo el local" ocupa a todos
  if exists (select 1 from turnos where negocio_id = v_neg.id and profesional_id is null
             and estado <> 'cancelado' and tstzrange(inicio, fin) && tstzrange(p_inicio, v_hasta)) then
    raise exception 'ocupado';
  end if;
  if p_profesional is not null and not exists (
    select 1 from (select id from profesionales where negocio_id = v_neg.id and activo
                   order by orden, nombre limit limite_profesionales(v_neg.plan)) h
    where h.id = p_profesional
  ) then
    raise exception 'profesional_invalido';
  end if;

  for v_pro in
    select p.* from (select * from profesionales where negocio_id = v_neg.id and activo
                     order by orden, nombre limit limite_profesionales(v_neg.plan)) p
    where (p_profesional is null or p.id = p_profesional)
      and (p.dias is null or v_dow = any(p.dias))
    order by (select count(*) from turnos t
              where t.profesional_id = p.id and t.estado in ('reservado','pendiente_pago','completado')
                and t.inicio >= p_inicio - interval '12 hours' and t.inicio < p_inicio + interval '12 hours'),
             p.orden, p.nombre
  loop
    begin
      insert into turnos (negocio_id, servicio_id, profesional_id, inicio, fin, nombre, telefono, precio, origen, estado, expira)
      values (v_neg.id, v_srv.id, v_pro.id, p_inicio, v_hasta, left(trim(p_nombre), 60), left(trim(p_telefono), 30),
              v_srv.precio, 'web', v_estado, v_expira)
      returning id into v_id;
      return v_id;
    exception when exclusion_violation then
      null; -- ese profesional está ocupado: probamos con el siguiente
    end;
  end loop;
  raise exception 'ocupado';
end $$;

-- Ver un turno propio (página de cancelación / pago). El id es secreto: solo lo tiene quien reservó.
create function ver_turno(p_id uuid)
returns table (inicio timestamptz, estado text, servicio text, negocio text, slug text,
               whatsapp text, puede_cancelar boolean, profesional text,
               sena_monto int, sena int, expira timestamptz)
language sql security definer set search_path = public stable as $$
  select t.inicio,
         case when t.estado = 'pendiente_pago' and t.expira < now() then 'cancelado' else t.estado end,
         s.nombre, n.nombre, n.slug, n.whatsapp,
         (t.estado in ('reservado','pendiente_pago') and t.inicio > now() + make_interval(mins => n.cancelacion_min)
            and not (t.estado = 'pendiente_pago' and t.expira < now())),
         p.nombre, n.sena_monto, t.sena, t.expira
  from turnos t join negocios n on n.id = t.negocio_id
  left join servicios s on s.id = t.servicio_id
  left join profesionales p on p.id = t.profesional_id
  where t.id = p_id and t.estado <> 'bloqueado';
$$;

create or replace function cancelar_turno(p_id uuid)
returns boolean
language plpgsql security definer set search_path = public as $$
declare v_n int;
begin
  update turnos t set estado = 'cancelado', cancelado_por = 'cliente'
  from negocios n
  where t.id = p_id and n.id = t.negocio_id and t.estado in ('reservado','pendiente_pago')
    and t.inicio > now() + make_interval(mins => n.cancelacion_min);
  get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'no_cancelable'; end if;
  return true;
end $$;

-- El dueño guarda (o borra) su token de Mercado Pago. No hay forma de leerlo de vuelta.
create or replace function guardar_token_mp(p_token text)
returns boolean
language plpgsql security definer set search_path = public as $$
declare v_neg uuid;
begin
  select id into v_neg from negocios where owner = auth.uid() order by created_at limit 1;
  if v_neg is null then raise exception 'sin_negocio'; end if;
  insert into negocio_secretos (negocio_id, mp_access_token, updated_at)
  values (v_neg, nullif(trim(p_token), ''), now())
  on conflict (negocio_id) do update set mp_access_token = excluded.mp_access_token, updated_at = now();
  return nullif(trim(p_token), '') is not null;
end $$;

create or replace function mp_conectado()
returns boolean
language sql security definer set search_path = public stable as $$
  select exists (select 1 from negocio_secretos s join negocios n on n.id = s.negocio_id
                 where n.owner = auth.uid() and coalesce(s.mp_access_token,'') <> '');
$$;

revoke all on function reservar(text, uuid, timestamptz, text, text, uuid) from public;
revoke all on function ocupados(text, timestamptz, timestamptz) from public;
revoke all on function ver_turno(uuid) from public;
revoke all on function cancelar_turno(uuid) from public;
revoke all on function guardar_token_mp(text) from public, anon;
revoke all on function mp_conectado() from public, anon;
grant execute on function reservar(text, uuid, timestamptz, text, text, uuid) to anon, authenticated;
grant execute on function ocupados(text, timestamptz, timestamptz) to anon, authenticated;
grant execute on function ver_turno(uuid) to anon, authenticated;
grant execute on function cancelar_turno(uuid) to anon, authenticated;
grant execute on function guardar_token_mp(text) to authenticated;
grant execute on function mp_conectado() to authenticated;

-- Monto de seña que se va a pedir (0 si el comercio no la pide o no conectó Mercado Pago)
create or replace function sena_activa(p_slug text)
returns int
language sql security definer set search_path = public stable as $$
  select case when n.plan = 'full' and exists (select 1 from negocio_secretos s where s.negocio_id = n.id and coalesce(s.mp_access_token,'') <> '')
              then n.sena_monto else 0 end
  from negocios n where n.slug = p_slug and n.activo;
$$;
revoke all on function sena_activa(text) from public;
grant execute on function sena_activa(text) to anon, authenticated;

-- =========================================================
-- FILA VIRTUAL (para locales que atienden por orden de llegada)
-- =========================================================

-- Modo de atención: turnos | fila | ambos (ambos: desde el plan Equipo)
alter table negocios add column if not exists modo             text    not null default 'turnos';
alter table negocios add column if not exists fila_pausada     boolean not null default false; -- el dueño la pausa a mano
alter table negocios add column if not exists fila_max         int     not null default 15;    -- máximo de personas esperando
alter table negocios add column if not exists fila_min_persona int     not null default 25;    -- minutos por persona (hasta que haya historial)
alter table negocios add column if not exists fila_cierre_min  int     not null default 30;    -- deja de anotar X min antes del cierre
alter table negocios add column if not exists pantalla         boolean not null default false; -- extra: pantalla del local (lo habilitás vos)
do $$ begin
  alter table negocios add constraint negocios_modo check (
    modo in ('turnos','fila','ambos') and fila_max between 1 and 200
    and fila_min_persona between 3 and 240 and fila_cierre_min between 0 and 240);
exception when duplicate_object then null; end $$;

create or replace function _controlar_modo() returns trigger
language plpgsql as $$
begin
  if new.plan = 'agenda' and new.modo = 'ambos' then
    raise exception 'modo_no_incluido';
  end if;
  return new;
end $$;
drop trigger if exists controlar_modo on negocios;
create trigger controlar_modo before insert or update of modo, plan on negocios
  for each row execute function _controlar_modo();

grant update (modo, fila_pausada, fila_max, fila_min_persona, fila_cierre_min) on negocios to authenticated;

create table if not exists fila (
  id             uuid primary key default gen_random_uuid(),
  negocio_id     uuid not null references negocios(id) on delete cascade,
  profesional_id uuid references profesionales(id) on delete set null,  -- null = "cualquiera"
  dia            date not null default (now() at time zone 'America/Argentina/Buenos_Aires')::date,
  numero         int  not null,
  nombre         text not null,
  telefono       text,
  estado         text not null default 'esperando'
                 check (estado in ('esperando','atendiendo','atendido','ausente','cancelado')),
  origen         text not null default 'web',   -- web | local
  creado         timestamptz not null default now(),
  avisado_at     timestamptz,                   -- el barbero le mandó el "te falta poco"
  inicio_at      timestamptz,                   -- lo empezaron a atender
  fin_at         timestamptz
);
create index if not exists fila_negocio_dia on fila (negocio_id, dia, estado, creado);

alter table fila enable row level security;
drop policy if exists fila_dueno on fila;
create policy fila_dueno on fila for all
  using (exists (select 1 from negocios n where n.id = negocio_id and n.owner = auth.uid()))
  with check (exists (select 1 from negocios n where n.id = negocio_id and n.owner = auth.uid()));
revoke all on fila from anon;
grant select, insert, update, delete on fila to authenticated;

-- ---------- Funciones internas ----------
create or replace function _hoy() returns date language sql stable as $$
  select (now() at time zone 'America/Argentina/Buenos_Aires')::date;
$$;

-- Profesionales que atienden hoy según el plan (vacío = local sin profesionales)
create or replace function _pros_hoy(p_neg uuid) returns setof profesionales
language sql stable security definer set search_path = public as $$
  select p.* from (
    select pr.* from profesionales pr join negocios n on n.id = pr.negocio_id
    where pr.negocio_id = p_neg and pr.activo
    order by pr.orden, pr.nombre limit (select limite_profesionales(plan) from negocios where id = p_neg)
  ) p
  where p.dias is null or extract(isodow from now() at time zone 'America/Argentina/Buenos_Aires')::int = any(p.dias);
$$;

-- Minutos promedio por persona: aprende de las últimas 20 atenciones; si hay pocas, usa el valor del ajuste
create or replace function _fila_promedio(p_neg uuid) returns int
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select greatest(5, least(120, round(avg(m))))::int from (
       select extract(epoch from fin_at - inicio_at) / 60 as m from fila
       where negocio_id = p_neg and estado = 'atendido' and inicio_at is not null and fin_at is not null
         and fin_at - inicio_at between interval '3 minutes' and interval '3 hours'
         and creado > now() - interval '30 days'
       order by fin_at desc limit 20) x
     having count(*) >= 5),
    (select fila_min_persona from negocios where id = p_neg));
$$;

-- ¿Se puede anotar gente ahora? abierta | pausada | cerrada | llena | sin_fila
create or replace function _fila_situacion(n negocios) returns text
language plpgsql stable security definer set search_path = public as $$
declare
  v_local timestamp := now() at time zone 'America/Argentina/Buenos_Aires';
  v_hora  time := v_local::time;
begin
  if not n.activo or n.modo not in ('fila','ambos') then return 'sin_fila'; end if;
  if n.fila_pausada then return 'pausada'; end if;
  if not exists (
    select 1 from jsonb_array_elements(coalesce(n.horarios -> extract(isodow from v_local)::int::text, '[]')) b
    where v_hora >= (b->>0)::time
      and v_hora < (b->>1)::time - make_interval(mins => n.fila_cierre_min)
  ) then return 'cerrada'; end if;
  if (select count(*) from fila where negocio_id = n.id and dia = _hoy() and estado = 'esperando') >= n.fila_max
    then return 'llena'; end if;
  return 'abierta';
end $$;

-- Cuántos hay adelante y cuánto falta (en minutos) para alguien de la fila
create or replace function _fila_calculo(p_id uuid, out adelante int, out espera_min int)
language plpgsql stable security definer set search_path = public as $$
declare f fila; v_prom int; v_nb int;
begin
  select * into f from fila where id = p_id;
  v_prom := _fila_promedio(f.negocio_id);
  if f.profesional_id is null then
    select count(*) into adelante from fila
      where negocio_id = f.negocio_id and dia = f.dia and estado = 'esperando' and creado < f.creado;
    select greatest(1, count(*)) into v_nb from _pros_hoy(f.negocio_id);
  else
    select count(*) into adelante from fila
      where negocio_id = f.negocio_id and dia = f.dia and estado = 'esperando' and creado < f.creado
        and (profesional_id = f.profesional_id or profesional_id is null);
    v_nb := 1;
  end if;
  espera_min := round((adelante + 0.5) * v_prom / v_nb);
end $$;

-- Alta en la fila con número del día (sin números repetidos aunque se anoten dos a la vez)
create or replace function _fila_insertar(p_neg uuid, p_nombre text, p_tel text, p_pro uuid, p_origen text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_num int;
begin
  perform pg_advisory_xact_lock(hashtext('fila:' || p_neg::text));
  select coalesce(max(numero), 0) + 1 into v_num from fila where negocio_id = p_neg and dia = _hoy();
  insert into fila (negocio_id, profesional_id, numero, nombre, telefono, origen)
  values (p_neg, p_pro, v_num, left(trim(p_nombre), 60), nullif(left(trim(coalesce(p_tel,'')), 30), ''), p_origen)
  returning id into v_id;
  return v_id;
end $$;

revoke all on function _pros_hoy(uuid) from public, anon, authenticated;
revoke all on function _fila_promedio(uuid) from public, anon, authenticated;
revoke all on function _fila_situacion(negocios) from public, anon, authenticated;
revoke all on function _fila_calculo(uuid) from public, anon, authenticated;
revoke all on function _fila_insertar(uuid, text, text, uuid, text) from public, anon, authenticated;

-- ---------- Funciones públicas de la fila ----------

-- Estado de la fila para quien se quiere anotar (sin datos personales)
create or replace function fila_estado(p_slug text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare n negocios; v_prom int; v_nb int; v_esp int;
begin
  select * into n from negocios where slug = p_slug and activo;
  if not found then return jsonb_build_object('situacion','sin_fila'); end if;
  v_prom := _fila_promedio(n.id);
  select greatest(1, count(*)) into v_nb from _pros_hoy(n.id);
  select count(*) into v_esp from fila where negocio_id = n.id and dia = _hoy() and estado = 'esperando';
  return jsonb_build_object(
    'situacion', _fila_situacion(n),
    'esperando', v_esp,
    'espera_min', round((v_esp + 0.5) * v_prom / v_nb),
    'promedio_min', v_prom,
    'profesionales', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', p.id, 'nombre', p.nombre,
        'espera_min', round(((select count(*) from fila f where f.negocio_id = n.id and f.dia = _hoy()
                               and f.estado = 'esperando' and (f.profesional_id = p.id or f.profesional_id is null)) + 0.5) * v_prom))
        order by p.orden, p.nombre)
      from _pros_hoy(n.id) p), '[]'::jsonb));
end $$;

create or replace function fila_anotarse(p_slug text, p_nombre text, p_telefono text, p_profesional uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare n negocios; v_sit text;
begin
  select * into n from negocios where slug = p_slug and activo;
  if not found then raise exception 'negocio_inexistente'; end if;
  v_sit := _fila_situacion(n);
  if v_sit <> 'abierta' then raise exception 'fila_%', v_sit; end if;
  if length(trim(coalesce(p_nombre,''))) < 2 then raise exception 'nombre_invalido'; end if;
  if length(regexp_replace(coalesce(p_telefono,''), '\D', '', 'g')) < 8 then raise exception 'telefono_invalido'; end if;
  if p_profesional is not null and not exists (select 1 from _pros_hoy(n.id) p where p.id = p_profesional) then
    raise exception 'profesional_invalido';
  end if;
  -- Una sola vez por día por teléfono (mientras siga esperando)
  if exists (select 1 from fila where negocio_id = n.id and dia = _hoy() and estado in ('esperando','atendiendo')
             and regexp_replace(telefono, '\D', '', 'g') = regexp_replace(p_telefono, '\D', '', 'g')) then
    raise exception 'ya_en_fila';
  end if;
  return _fila_insertar(n.id, p_nombre, p_telefono, p_profesional, 'web');
end $$;

-- Mi lugar en la fila. El id es secreto: solo lo tiene quien se anotó.
create or replace function fila_mi_lugar(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare f fila; n negocios; c record;
begin
  select * into f from fila where id = p_id;
  if not found then return null; end if;
  select * into n from negocios where id = f.negocio_id;
  select * into c from _fila_calculo(p_id);
  return jsonb_build_object(
    'numero', f.numero, 'nombre', f.nombre,
    'estado', case when f.estado = 'esperando' and f.dia < _hoy() then 'cancelado' else f.estado end,
    'adelante', c.adelante, 'espera_min', c.espera_min,
    'profesional', (select nombre from profesionales where id = f.profesional_id),
    'negocio', n.nombre, 'slug', n.slug, 'whatsapp', n.whatsapp, 'direccion', n.direccion,
    'color', case when n.plan = 'agenda' then null else n.color end);
end $$;

create or replace function fila_salir(p_id uuid)
returns boolean language plpgsql security definer set search_path = public as $$
declare v_n int;
begin
  update fila set estado = 'cancelado' where id = p_id and estado = 'esperando';
  get diagnostics v_n = row_count;
  return v_n > 0;
end $$;

-- Pantalla del local: números y nombres de pila (nada de teléfonos). Solo si el extra está habilitado.
create or replace function fila_pantalla(p_slug text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare n negocios;
begin
  select * into n from negocios where slug = p_slug and activo;
  if not found or not n.pantalla then return jsonb_build_object('habilitada', false); end if;
  return jsonb_build_object(
    'habilitada', true, 'negocio', n.nombre, 'color', n.color, 'situacion', _fila_situacion(n),
    'atendiendo', coalesce((select jsonb_agg(jsonb_build_object('numero', f.numero, 'nombre', split_part(f.nombre,' ',1),
                      'profesional', (select nombre from profesionales where id = f.profesional_id)) order by f.inicio_at)
                    from fila f where f.negocio_id = n.id and f.dia = _hoy() and f.estado = 'atendiendo'), '[]'::jsonb),
    'esperando', coalesce((select jsonb_agg(jsonb_build_object('numero', x.numero, 'nombre', split_part(x.nombre,' ',1)) order by x.creado)
                    from (select * from fila f where f.negocio_id = n.id and f.dia = _hoy() and f.estado = 'esperando'
                          order by f.creado limit 12) x), '[]'::jsonb),
    'total_esperando', (select count(*) from fila f where f.negocio_id = n.id and f.dia = _hoy() and f.estado = 'esperando'));
end $$;

-- ---------- Funciones del dueño ----------

-- "Llamar al siguiente": termina al que estaba atendiendo ese profesional y toma al próximo que le corresponde.
-- Dos barberos tocando a la vez nunca se llevan a la misma persona.
create or replace function fila_siguiente(p_profesional uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_neg uuid; v_id uuid;
begin
  select id into v_neg from negocios where owner = auth.uid() order by created_at limit 1;
  if v_neg is null then raise exception 'sin_negocio'; end if;
  update fila set estado = 'atendido', fin_at = now()
   where negocio_id = v_neg and estado = 'atendiendo' and profesional_id is not distinct from p_profesional;
  select id into v_id from fila
   where negocio_id = v_neg and dia = _hoy() and estado = 'esperando'
     and (p_profesional is null or profesional_id is null or profesional_id = p_profesional)
   order by creado limit 1 for update skip locked;
  if v_id is null then return null; end if;
  update fila set estado = 'atendiendo', inicio_at = now(),
                  profesional_id = coalesce(p_profesional, profesional_id)
   where id = v_id;
  return v_id;
end $$;

-- "+ Anotar" desde el local (el que entra caminando). Sin control de horario ni de máximo.
create or replace function fila_agregar(p_nombre text, p_telefono text default null, p_profesional uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_neg uuid;
begin
  select id into v_neg from negocios where owner = auth.uid() order by created_at limit 1;
  if v_neg is null then raise exception 'sin_negocio'; end if;
  if length(trim(coalesce(p_nombre,''))) < 2 then raise exception 'nombre_invalido'; end if;
  return _fila_insertar(v_neg, p_nombre, p_telefono, p_profesional, 'local');
end $$;

revoke all on function fila_estado(text) from public;
revoke all on function fila_anotarse(text, text, text, uuid) from public;
revoke all on function fila_mi_lugar(uuid) from public;
revoke all on function fila_salir(uuid) from public;
revoke all on function fila_pantalla(text) from public;
revoke all on function fila_siguiente(uuid) from public, anon;
revoke all on function fila_agregar(text, text, uuid) from public, anon;
grant execute on function fila_estado(text) to anon, authenticated;
grant execute on function fila_anotarse(text, text, text, uuid) to anon, authenticated;
grant execute on function fila_mi_lugar(uuid) to anon, authenticated;
grant execute on function fila_salir(uuid) to anon, authenticated;
grant execute on function fila_pantalla(text) to anon, authenticated;
grant execute on function fila_siguiente(uuid) to authenticated;
grant execute on function fila_agregar(text, text, uuid) to authenticated;

-- ---------- Tiempo real para el panel del comercio ----------
do $$ begin
  alter publication supabase_realtime add table turnos;
exception when duplicate_object then null;
end $$;
do $$ begin
  alter publication supabase_realtime add table fila;
exception when duplicate_object then null;
end $$;
