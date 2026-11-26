-- =========================================================
-- Dar de alta un comercio nuevo
-- 1) En Supabase > Authentication > Users > "Add user", creá el usuario
--    del dueño con su email y una contraseña.
-- 2) Cambiá los datos de abajo y corré este archivo en el SQL Editor.
-- =========================================================

with dueno as (
  select id from auth.users where email = 'barbero@ejemplo.com'   -- <- email del dueño
), neg as (
  insert into negocios (slug, nombre, whatsapp, direccion, plan, owner)
  select 'barberia-del-canal',                                      -- <- va en el link
         'Barbería del Canal',
         '5492941000000',                                           -- <- WhatsApp del local
         'Villa Regina, Río Negro',
         'agenda',                                                  -- <- plan: agenda | equipo | full
         id
  from dueno
  returning id
)
insert into servicios (negocio_id, nombre, descripcion, duracion_min, precio, orden)
select neg.id, s.nombre, s.descripcion, s.duracion, s.precio, s.orden
from neg, (values
  ('Corte',         'Tijera o máquina, con lavado', 30,  8000, 1),
  ('Corte + barba', 'El combo completo',            60, 11000, 2),
  ('Barba',         'Perfilado y toalla caliente',  30,  5000, 3),
  ('Corte niño',    'Hasta 12 años',                30,  6500, 4)
) as s(nombre, descripcion, duracion, precio, orden);

-- Para cambiar horarios más adelante (1=lunes ... 7=domingo):
-- update negocios set horarios = '{"1":[["09:00","13:00"],["16:00","20:30"]],"6":[["09:00","14:00"]]}'
-- where slug = 'barberia-del-canal';
