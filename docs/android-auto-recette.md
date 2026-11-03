# Fiche de recette Android Auto (lots 20, 23 et 24)

À dérouler dans la voiture, téléphone Android branché (ou en sans-fil), avec un second terminal qui joue le PCO (iPhone, PC ou navigateur). Compter 20 minutes. Noter pour chaque étape : conforme, non conforme (photo de l'écran de la voiture), ou non testable.

Ce que la CI vérifie déjà sans voiture : les données envoyées à la voiture (`test/lot17_voiture_test.dart`, `test/lot20_auto_*_test.dart`) et les écrans de la voiture avec la bibliothèque de test de Google (`third_party/sarcade_car/android/src/test`, job `android-build`, étape « Car screen tests »). Ce qui reste à voir en voiture : les couleurs réellement appliquées par Android Auto, la lecture à voix haute, l'ouverture de Maps ou Waze.

## 0. Préparer

1. Installer la dernière version de test (Google Play, piste Test interne).
2. Sur le téléphone : ouvrir SARCADE, rejoindre l'événement, vérifier dans Paramètres › Profil que l'**indicatif** est renseigné (il relie les terminaux d'une même personne).
3. Si possible, un second terminal du porteur (Surface ou PC) avec **le même indicatif** dans Paramètres › Profil.
4. Google Maps ou Waze installé sur le téléphone.
5. Brancher le téléphone, ouvrir SARCADE dans Android Auto.

## 1. Écran stable (carte « l'écran clignote »)

| # | Action | Résultat attendu |
|---|--------|------------------|
| 1.1 | Onglet Ordres avec un ordre en cours, voiture à l'arrêt, observer 1 minute | La ligne ne clignote plus, aucun parasite |
| 1.2 | Onglet Messages avec beaucoup de messages, défiler vers le bas, attendre 1 minute | La liste reste en place, la barre de défilement ne réapparaît pas |
| 1.3 | Rouler quelques minutes, onglet Points | Distances par paliers (« 250 m », « 3 km », « 3,5 km »), mises à jour au plus toutes les 15 s |
| 1.4 | Le PCO envoie un message | Il apparaît dans l'onglet Messages en quelques secondes |

## 2. Onglet Points (cartes « relais » et « boutons ronds gris »)

| # | Action | Résultat attendu |
|---|--------|------------------|
| 2.1 | Ouvrir l'onglet Points | D'abord les points de l'événement, puis au plus 10 points hauts (icône montagne) avec leur altitude ; aucun relais |
| 2.2 | Regarder la ligne d'un point | Courte, non coupée : « 3 km NO », « 3 km NE · Point haut · 412 m » |
| 2.3 | Regarder à droite de chaque point | Une flèche d'itinéraire (plus de rond gris vide) |
| 2.4 | ~~Bouton SOS rond~~ | Remplacé au lot 23 par le SOS de la barre du haut : voir 4.1 |
| 2.5 | Toucher la flèche d'un point | Google Maps ou Waze s'ouvre **déjà guidé** vers le point |
| 2.6 | Revenir à SARCADE, toucher la ligne d'un autre point (pas la flèche) | Même résultat qu'en 2.5 |
| 2.7 | Si aucune application de navigation ne s'ouvre | Un message clair apparaît (« Navigation impossible : installez Google Maps ou Waze sur le téléphone ») ; noter lequel des deux cas |

## 3. Ordres de déplacement (carte « ordres peu utilisables »)

| # | Action | Résultat attendu |
|---|--------|------------------|
| 3.1 | SARCADE affiché dans la voiture, le PCO envoie un ordre à ce téléphone | Le message est lu à voix haute (comme avant) **et** une alerte apparaît par-dessus SARCADE : en titre le **nom du point**, dessous « Ordre de déplacement · PCO… · 3 km NO », boutons **Y aller** et **Voir** |
| 3.2 | Toucher « Voir » | L'écran de l'ordre s'ouvre (nom, consigne, Accepter / Refuser) |
| 3.3 | Revenir, onglet Ordres | L'ordre est dans la liste, avec coche (Accepter) et croix (Refuser) à droite |
| 3.4 | Le PCO envoie un second ordre ; cette fois toucher « Y aller » | Google Maps ou Waze guidé vers le point |
| 3.5 | Mettre Maps ou Waze au premier plan dans la voiture, le PCO envoie un troisième ordre | Une notification de la voiture avec le nom du point, « Y aller » et « Voir » |
| 3.6 | Regarder les notifications de messages | Les ordres du PCO sont regroupés dans **une seule** notification de conversation, le dernier ordre affiché |
| 3.7 | Téléphone verrouillé dans la poche depuis plusieurs minutes, le PCO envoie un ordre | L'onglet Ordres le montre en moins de 10 secondes (plus « Aucun ordre ») |
| 3.8 | Second terminal du porteur (même indicatif) : le PCO lui envoie un ordre | L'ordre apparaît aussi dans l'onglet Ordres de la voiture ; Accepter depuis la voiture est accepté par le serveur (statut « accepté » chez le PCO) |
| 3.9 | Accepter un ordre, puis dans l'onglet Ordres | Boutons drapeau (Je suis arrivé) et flèche d'itinéraire |

## 4. Lot 23 : SOS en haut, Équipe, naviguer vers un opérateur

Au lot 23, la voiture montrait **une rubrique à la fois** : bouton « Rubriques » (trois traits) et « SOS » en haut à droite, plus d'onglets ni de bouton rond. **Le lot 24 revient aux onglets** (section 5) : les étapes 4.1, 4.2 et 4.11 sont remplacées par 5.1 à 5.4 ; les autres se font dans l'onglet Équipe.

| # | Action | Résultat attendu |
|---|--------|------------------|
| 4.1 | Ouvrir SARCADE dans la voiture, regarder en haut à droite | Bouton « Rubriques » (trois traits) et bouton « SOS » avec icône rouge ; plus aucun bouton rond en bas à droite, dans aucune rubrique |
| 4.2 | Toucher « SOS », puis Annuler | L'écran de confirmation de détresse s'ouvre, Annuler revient sans rien envoyer |
| 4.3 | « Rubriques » › Équipe | Seulement les opérateurs vus depuis moins de 24 h (plus de PC-demo « vu il y a 8 j » ni PCO « 2 j ») |
| 4.4 | Aucun autre opérateur actif depuis 24 h | Message « Personne d'autre en ligne » |
| 4.5 | Équipe, regarder à droite d'un opérateur | Une flèche d'itinéraire ; pas de flèche pour un opérateur sans position |
| 4.6 | Toucher la flèche d'un opérateur | Google Maps ou Waze s'ouvre guidé vers sa dernière position connue |
| 4.7 | Revenir, toucher la ligne (pas la flèche) | Même résultat |
| 4.8 | L'opérateur se déplace (second terminal en marche) ; revenir à SARCADE, toucher de nouveau sa flèche | La destination est mise à jour vers sa nouvelle position |
| 4.9 | Observer l'onglet Équipe 2 minutes pendant que l'opérateur bouge | Pas de clignotement ; l'âge par paliers (« vu il y a moins de 5 min », « 5 min », « 10 min », « 15 min ») |
| 4.10 | Opérateur dont la position a plus de 15 minutes | La ligne indique « position de 20 h 05 » (heure de sa dernière position) |
| 4.11 | Changer 6 fois de suite de rubrique (Rubriques › Messages, Ordres, Points, Équipe…) | Aucun message d'erreur d'Android Auto ; noter si un écran « trop d'étapes » apparaît |

## 5. Lot 24

### Retour aux onglets, SOS en bouton rond

| # | Action | Résultat attendu |
|---|--------|------------------|
| 5.1 | Ouvrir SARCADE dans la voiture | Onglets Messages, Ordres, Points, Équipe en haut ; plus de bouton « Rubriques » |
| 5.2 | Regarder en bas à droite, dans chaque onglet | Un bouton rond avec « SOS » écrit en blanc (sur la couleur choisie par Android Auto) |
| 5.3 | Toucher le bouton rond « SOS », puis Annuler | L'écran de confirmation de détresse s'ouvre, Annuler revient sans rien envoyer |
| 5.4 | Changer 6 fois de suite d'onglet | Aucun message d'erreur d'Android Auto, pas d'écran « trop d'étapes » |
| 5.5 | Onglet Équipe | Flèche d'itinéraire à droite de chaque opérateur ; seulement les opérateurs vus depuis moins de 24 h (comme 4.3 à 4.5) |

## 6. Après la recette

- Reporter les résultats dans la carte du Kanban (colonne « À recetter ») avec les photos.
- Pour le SOS (5.2) : depuis le lot 24, `CarUi.SOS_IN_STRIP = false` (onglets, bouton rond) ; revenir à une rubrique à la fois avec le SOS en haut = remettre `true` (une ligne).
