# ONE PIECE: GRAND SEA

Нативная 3D-игра на Godot 4 (Compatibility renderer): морское приключение, вдохновлённое One Piece и Sea of Thieves. Игра запускается как отдельное приложение для Windows или Linux, **не через браузер**.

## Содержимое

- Океан и процедурный архипелаг, острова с растительностью и поселениями;
- Парусный корабль, штурвал, запрет проникновения корпуса в берег;
- Луффи и Зоро (**Tab** переключает персонажа), разные приёмы;
- Пираты-охранники, которые преследуют игроков и атакуют;
- Дьявольские плоды, золото и главный приз на Laugh Tale;
- Отдельное плавание в воде и ходьба по суше;
- Мультиплеер в локальной сети (Godot ENet/UDP);
- Docker-сервер и сборка нативных клиентов GitHub Actions.

Для героев в игровой сборке используются только **две анимированные модели KayKit Adventurers** (CC0), вместе ~7.23 МБ, с небольшими аксессуарами Луффи и Зоро. [Лицензия](assets/characters/ASSET_LICENSE.txt).

## Запуск

Смотрите [QUICKSTART.md](QUICKSTART.md). Движок вручную ставить не нужно: Docker собирает игру, а готовые сборки доступны в GitHub Actions.

**Статус:** развивающийся технический прототип. Модели — стилизованные фан-версии персонажей, а не официальные ресурсы аниме. Производительность и мультиплеер нужно проверять на целевых слабых ПК.


### Обновлённое управление

WASD — идти относительно камеры; за штурвалом — корабль. ПКМ (удерживать) — вращать камеру, ЛКМ — стрелять по направлению курсора, Space — ближняя атака, Tab — Луффи/Зоро, Shift — бег, F — вода/возвращение, G — собрать плод/золото.

Картинка/рендер улучшены без тяжёлых текстур: геометрические вырезы океана, дополнительные камни и пальмы, более подробный рельеф. Режим Low сохраняется. Стены проверяются на сервере и имеют клиентские физические коллайдеры. Новые тесты запускаются автоматически.


## Kill score & varied islands

Pirate guards now award **+100 points and +1 kill** to the player who lands the final blow, for both melee and ranged combat; repeated hits on a dead guard cannot farm points. Scores appear in the HUD and a shared LAN scoreboard.

Island silhouettes are no longer perfect circles. Terrain varies by biome: tropical hills, jungle ridges, snowy mountains, desert dunes, volcanic craters, rocky cliffs, mesa plateaus, lagoon islands and Laugh Tale. Server navigation, land meshes, shoreline clipping and ship collision reference the **same deterministic coastline function**.

The previous water-triangle clipping algorithm incorrectly clipped polygons against a non-convex outside-of-circle area. The new adaptive shoreline tessellation entirely omits uncertain cells, down to approximately 1.9 m, so water triangles never intersect land. An automated triangle-level test verifies this.


## Pirates, Devil Fruits and island spacing (2026-11)

- All 56 islands have server-side pirate spawns: three recognizable types (cutlass raider, bandana bandit, armored brute). Enemies continue guarding looted islands; defeated pirates respawn after 90 seconds when players return.
- Ship helm: A turns LEFT, D turns RIGHT when sailing forward. The archipelago has been condensed around Dawn Island, with two guaranteed early destinations; Laugh Tale remains a distant objective.
- Defeat the island pirates, then press **G** near its center to obtain its Devil Fruit. Depending on the island the power is **SPEED ×2**, **DOUBLE JUMP**, or **DAMAGE +1**. Unique powers accumulate; re-collecting the same type does not stack it further.
- **Space** jumps, then jumps a second time mid-air when DOUBLE JUMP is unlocked; **J** is melee attack; **LMB** shoots; **Tab** switches Luffy/Zoro. Powers appear in the HUD.
- Fruit ownership is persisted with world saves. In this LAN prototype saved player IDs are not identity-secure accounts: a returning player with a different peer ID may not recover their fruit power.
- Both playable hero costumes have improved recognizability through bone-attached 3D accessories and clothing. They remain stylized fan interpretations built on CC0 rigs, not official anime models.

