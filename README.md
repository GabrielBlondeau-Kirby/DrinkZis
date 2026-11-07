# DrinkZis

Addon WoW : un « sac » à potions flottant. Une icône ronde ouvre et ferme un
cadre qui range les potions des sacs par catégorie.

| Catégorie | Contenu |
|-----------|---------|
| **Vie**    | potions de soins, pierres de soins |
| **Mana**   | potions de mana, gemmes de mana |
| **Combat** | autres potions (vitesse, action libre, protections, rage…) |
| **Buffs**  | élixirs, flacons, parchemins |

Un emplacement par type d'objet, avec la quantité totale et la recharge.
Chaque ligne commence par l'icône de sa catégorie (nom au survol).

## Utilisation

- Clic sur l'icône ronde : ouvrir / fermer le sac (marche aussi en combat).
- Clic sur une potion : l'utiliser.
- **Maj + glisser** l'icône : déplacer l'ensemble.
- Icône autour de la minimap : clic gauche ouvre / ferme le sac (aussi en
  combat), clic droit ouvre les options, glisser la fait tourner.
- `/dz` : options (aussi dans Échap → Options → AddOns). `/dz reset` : position.
  `/dz minimap` : afficher / masquer l'icône de la minimap.

### Options

- Ouverture automatique en combat, fermeture à la sortie (seulement si c'est
  le combat qui l'a ouvert).
- Catégories affichées.
- Thèmes : Sombre, Doré, Arcane, Gangrène, Sang.
- Verrouiller la position.
- Icône ronde transparente hors combat : elle redevient opaque au survol et
  en combat.
- Langue de l'interface : Auto (langue du jeu), English, Français. Elle ne
  change pas le classement des potions, qui reconnaît les clients anglais et
  français dans tous les cas.

## Limites

- En combat, le jeu interdit de déplacer ou créer des boutons : une nouvelle
  potion n'apparaît qu'à la sortie du combat. Les quantités et recharges, elles,
  se mettent à jour en direct.
- Le classement se base sur le nom et la description de l'objet : seuls les
  clients anglais et français sont reconnus.

## Licence

MIT — voir [LICENSE](LICENSE).
