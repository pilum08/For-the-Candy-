# Sir_DON — карта проекта (кратко)

2D-игра на Godot 4.7 (GDScript), главная сцена `main.tscn`. Арт 1:1, единый масштаб —
`ArtScale.gd`. Ручные настройки — `docs/SETUP.md`.

## Игрок
- `Player.gd` — герой «Дон»: движение, прицел, стрельба, подбор/носка предметов, смерть. @export: art_scale, player_scale, speed, projectile_scene, pickup_radius; signal died
- `Player.tscn` — герой (CharacterBody2D, группа `player`: Collider, PickupZone, Visual, Camera)
- `Rig.gd` — сборка куклы из PNG по таблице частей (для Player.RIG)
- `Corpse.gd` — труп врага (RigidBody2D), носимый предмет; группы `corpses`, `carryables`. @export: mob_rig, enemy_scale, corpse_world_z
- `Corpse.tscn` — сцена трупа
- `CameraFollow.gd` — камера уровня, герой не по центру. @export: anchor_x, left_limit, shake_enabled (тряска `shake(intensity, duration)` — зовёт пушка)

## Мобы
- `Enemy.gd` — враг: погоня, удар касанием, урон, смерть, труп. @export: max_hp, speed, contact_damage, corpse_scene; signals died, attacked; нет места под труп — разлёт частей (MobDeathBurst.gd)
- `Enemy.tscn` — базовый враг (CharacterBody2D, группа `enemies`, Visual.rig = enemy_yellow.tres)
- `Enemy_test.tscn` — тестовая копия Enemy (красный modulate; запись в spawn_table_level1)
- `MobRigData.gd` — паспорт вида моба (.tres): parts, art_scale, walk/idle_poses, лица, труп
- `MobVisual.gd` — визуал моба: строит суставы по паспорту, листает позы, подменяет лицо
- `enemy_yellow.tres` — паспорт жёлтого моба

## Предметы и снаряды
- `Cannon.gd` — пушка: носится, стреляет ядром, ломается; группа `carryables`. @export: ball_scene, ball_data, carry_offset, fall_fail_depth
- `Cannon.tscn` — сцена пушки
- `CannonFire.gd` — вспышка/дымок из дула в момент выстрела (ставит и масштабирует Cannon). @export: fire_textures, smoke_textures, fire_frame_duration, smoke_frame_duration, smoke_delay
- `CannonFire.tscn` — сцена вспышки (спрайты Fire, Smoke)
- `Projectile.gd` — снаряд по дуге: попадание/промах. signals hit_target, hit_tower, missed
- `Projectile.tscn` — снаряд (Area2D)
- `ProjectileData.gd` — данные типа снаряда. @export: texture, speed, damage, pierce_enemies, can_damage_tower, report_miss
- `stone_projectile.tres` — камень; `cannonball.tres` — ядро пушки
- `SpikeZone.gd` — шипы: касание = Player.die()
- `SpikeZone.tscn` — не используется (скрипт применён прямо в Pit.tscn / PitSection.tscn)

## Уровень
- `main.tscn` — уровень: Ground, Pit, Fortification, Tower, Player+Camera, Encounter1/2, WaveTrigger, PlayersWall, MobSpawner, WaveManager, LevelController, Cannon
- `Tower.gd` — башня: спавн из двери, HP, разрушение; группа `tower`; signal destroyed. @export: max_hp, group_size, group_interval, max_alive, activation_size
- `Tower.tscn` — сцена башни
- `Pit.gd` — яма из секций. signals section_filled(index), pit_completed. @export: section_count, pit_width, pit_depth; корень в группе `pits`
- `Pit.tscn` — сцена ямы (Bottom, SpikeZone, Sections)
- `PitSection.gd` — ячейка ямы: ловит труп, гасит смерть, включает пол; signal filled(index)
- `PitSection.tscn` — сцена ячейки (DeathZone, CatchZone, Floor)
- `MobSpawner.gd` — спавн мобов по таблице за краем экрана; группа `mobs`; signals mob_spawned, mob_died. @export: default_table, prototype_scene, spawn_margin
- `SpawnTable.gd` — взвешенная таблица спавна; `SpawnEntry.gd` — запись (mob_scene / mob_data, weight)
- `spawn_table_level1.tres` — таблица уровня 1
- `WaveManager.gd` — волны по расписанию. signals wave_started, wave_cleared, all_waves_cleared. @export: waves, common_table
- `WaveData.gd` — паспорт волны; `wave_1.tres`, `wave_2.tres`, `wave_3.tres` — волны
- `WaveTrigger.gd` — запуск волн + запор камеры и стена. @export: lock_camera, связи (wave_manager, camera, left_wall)
- `WaveTrigger.tscn` — сцена триггера укрепления
- `EncounterTrigger.gd` — засада: спавн 1–2 мобов. @export: count, spawn_interval, once, spawn_table
- `EncounterTrigger.tscn` — сцена засады
- `LevelController.gd` — исход забега. signals level_won, level_failed(reason). @export: fail_reload_delay, corpse_reserve, decay_chance_when_pit_full; get_max_corpses(), can_spawn_corpse(), is_any_pit_full() (подписка на pit_completed ям)
- `ArtScale.gd` — единый масштаб арта (hero_scale / scale_of) — утилита

## Утилиты
- `DeathBurst.gd` — разлёт частей на обломки при смерти героя. @export: debris_scene, speed_min/max, debris_layer/mask
- `Debris.tscn` — обломок (RigidBody2D, слой 7)
- `DebugKeys.gd` — единый выключатель отладочных клавиш (ENABLED)
- `MobDeathBurst.gd` — разлёт частей моба вместо трупа при исчерпании лимита (обломки моба падают сквозь землю и гаснут за экраном)

## Слои столкновений (project.godot)
1 игрок, 2 враги, 3 земля и стены, 4 снаряды, 5 тела, 6 замороженные тела (не используется),
7 обломки, 8 предметы, 9 башня. Бит слоя = 2^(номер−1). Маски сцен — docs/SETUP.md, разд. 1.

## Управление (project.godot → Ввод)
move_left — A / ←, move_right — D / →, shoot — ЛКМ, interact — E.
Отладка (только при DebugKeys.ENABLED / флагах): F1 — спавн моба, F2 — волны, F3 — урон башне.

## Группы (names)
player — герой; enemies — враги; mobs — все заспавненные мобы; corpses — трупы; carryables — носимые
(трупы, пушка); tower — башня; mob_spawner, wave_manager, level_controller — узлы уровня;
camera — камера; wave_wall — стена волн; pits — ямы (для расчёта лимита трупов).

