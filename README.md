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

## Utilisation

- Clic sur l'icône ronde : ouvrir / fermer le sac (marche aussi en combat).
- Clic sur une potion : l'utiliser.
- **Maj + glisser** l'icône : déplacer l'ensemble.
- `/dz` : options (aussi dans Échap → Options → AddOns). `/dz reset` : position.

### Options

- Ouverture automatique en combat, fermeture à la sortie (seulement si c'est
  le combat qui l'a ouvert).
- Catégories affichées.
- Thèmes : Sombre, Doré, Arcane, Gangrène, Sang.
- Verrouiller la position.

## Limites

- En combat, le jeu interdit de déplacer ou créer des boutons : une nouvelle
  potion n'apparaît qu'à la sortie du combat. Les quantités et recharges, elles,
  se mettent à jour en direct.
- Le classement se base sur le nom et la description de l'objet (français et
  anglais).
