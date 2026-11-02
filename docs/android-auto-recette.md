# Fiche de recette Android Auto (lot 20)

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
| 2.4 | Regarder le bouton SOS rond | Icône « SOS » rouge. Noter la couleur du fond du bouton. Si l'icône n'est pas rouge et lisible : non conforme, appliquer le repli décrit dans la PR (SOS dans la barre du haut) |
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

## 4. Après la recette

- Reporter les résultats dans la carte du Kanban (colonne « À recetter ») avec les photos.
- Pour le SOS (2.4) : si non conforme, demander le passage au repli (une ligne, voir la PR).
