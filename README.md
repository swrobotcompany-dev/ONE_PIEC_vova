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
