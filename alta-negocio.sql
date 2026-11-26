-- =========================================================
-- Dar de alta un comercio nuevo
-- 1) En Supabase > Authentication > Users > "Add user", creá el usuario
--    del dueño con su email y una contraseña (marcá Auto Confirm User).
-- 2) Cambiá SOLO los datos marcados con <- y corré este archivo en el SQL Editor.
--    Si algo está mal (por ejemplo el email), te avisa con un error claro.
-- =========================================================

do $$
declare
  -- ------- DATOS DEL COMERCIO -------
  v_email     text := 'barbero@ejemplo.com';        -- <- email del dueño (el mismo del usuario creado)
  v_slug      text := 'barberia-prueba';            -- <- va en el link: minúsculas, sin espacios ni tildes
  v_nombre    text := 'Barbería de Prueba';         -- <- nombre que ven los clientes
  v_whatsapp  text := '5492941000000';              -- <- WhatsApp del local: 549 + área + número
  v_direccion text := 'Villa Regina, Río Negro';    -- <- dirección
  v_plan      text := 'full';                       -- <- agenda | equipo | full
  v_modo      text := 'turnos';                     -- <- turnos | fila | ambos (ambos: plan equipo o full)
  -- ----------------------------------
  v_owner uuid;
  v_neg   uuid;
begin
  select id into v_owner from auth.users where lower(email) = lower(trim(v_email));
  if v_owner is null then
    raise exception 'No existe ningún usuario con el email "%". Crealo en Authentication > Users o corregí el email.', v_email;
  end if;
  if exists (select 1 from negocios where owner = v_owner) then
    raise exception 'Ese usuario ya tiene un comercio asignado. Para cambiarle los datos usá el panel (Ajustes).';
  end if;
  if exists (select 1 from negocios where slug = v_slug) then
    raise exception 'Ya existe un comercio con el slug "%". Elegí otro.', v_slug;
  end if;

  insert into negocios (slug, nombre, whatsapp, direccion, plan, modo, owner)
  values (v_slug, v_nombre, v_whatsapp, v_direccion, v_plan, v_modo, v_owner)
  returning id into v_neg;

  -- ------- SERVICIOS (nombre, descripción, minutos, precio) -------
  insert into servicios (negocio_id, nombre, descripcion, duracion_min, precio, orden)
  select v_neg, s.nombre, s.descripcion, s.duracion, s.precio, s.orden
  from (values
    ('Corte',         'Tijera o máquina, con lavado', 30,  8000, 1),
    ('Corte + barba', 'El combo completo',            60, 11000, 2),
    ('Barba',         'Perfilado y toalla caliente',  30,  5000, 3),
    ('Corte niño',    'Hasta 12 años',                30,  6500, 4)
  ) as s(nombre, descripcion, duracion, precio, orden);

  raise notice 'Listo: comercio "%" creado. Link para clientes: …/?n=%', v_nombre, v_slug;
end $$;

-- Para cambiar horarios más adelante (1=lunes ... 7=domingo) también se puede desde el panel (Ajustes).
