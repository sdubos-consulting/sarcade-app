# Relevés et résection

Ces fonctions n'apparaissent que si le module ADRASEC est actif pour l'événement et autorisé pour votre compte.

## Prendre un relevé

1. Faites un **appui long** sur la carte, près de votre position (30 m environ) : le relevé démarre depuis votre position GPS. Sur ordinateur, faites un clic long.
2. Appui long ailleurs : le menu du point s'ouvre ; choisissez **Relevé**. Le point touché devient le point de prise.
3. Le relevé peut aussi partir du **Convertisseur de coordonnées** (action « Relevé »).

Le calque « Relevés » se réaffiche tout seul s'il était masqué.

## Pendant le relevé

- En haut, l'azimut en grands chiffres, suivi de **vrai** (ou **saisi** s'il a été tapé), et l'azimut magnétique.
- Avec la boussole : **visez la source avec le haut du téléphone**. L'application ajoute la déclinaison magnétique pour donner l'azimut vrai.
- Si l'application indique « Boussole peu précise », décrivez un 8 avec le téléphone pour la calibrer.
- Au moment d'**Enregistrer**, la boussole fait une moyenne sur 2 secondes : tenez la visée.
- **Sans boussole** (ordinateur, certaines tablettes, navigateur web) : tapez l'azimut vrai dans le champ « Azimut (°) ».
- **À la souris** : une flèche part du point et suit la souris. Clic pour fixer, Maj pour avancer par pas de 5°, Échap ou clic droit pour annuler.

En bas :

- **Signal recherché** : 121,500 MHz (balise de détresse réelle), 406,000 MHz (Cospas-Sarsat), 121,375 MHz (balise d'exercice, marquée EXERCICE), puis les signaux déjà utilisés dans l'événement, puis **Autre…** pour créer un signal (fréquence ou libellé, réel ou exercice).
- **Force du signal (S1 à S9)** : facultative ; elle compte dans le calcul de la zone.
- Une phrase indique comment ce relevé changerait la zone probable.
- Boutons : **Enregistrer**, **Saisir l'azimut**, **Prendre le centre de la carte comme position**.

Sans réseau, le relevé est gardé sur l'appareil et part dès que la liaison revient.

## Ce que montre la carte

- Chaque relevé est une ligne (10 km par défaut) avec un cône de ±5°. La couleur dépend du signal : violet pour 406, rouge pour 121,5, bleu pour 121,375.
- Dans Calques, « Couleur des relevés » permet de colorer par **Signal** ou par **Opérateur**.
- Le point de prise porte les initiales de l'opérateur ; les croisements sont de petits points.

## Zone probable

- Elle est calculée sur chaque appareil, **signal par signal**, à partir des croisements des relevés.
- Les croisements trop fermés (moins de 20°) sont ignorés ; un relevé incohérent avec les autres est écarté automatiquement et devient une ligne grise en tirets.
- Recherche réelle : cercle rouge plein. Exercice : contour orange en tirets avec la pastille « EX ».
- L'étiquette donne la taille, le nombre de relevés et le nombre d'écartés ; avec moins de 3 relevés, elle dit « zone approximative ».
- Toucher la zone ouvre son détail. Le choix **Auto / Plusieurs balises / Une seule balise** est enregistré sur le serveur pour tous.

## Fiche d'un relevé

Touchez la ligne d'un relevé pour voir l'azimut, le signal, l'auteur, l'heure, la force et la méthode (boussole, saisi, carte).

- **PCO seulement** : dans « Zone probable », **Écarter** ou **Garder** le relevé à la main, ou revenir à **Auto**.
- **Auteur ou PCO** : **Ajuster sur la carte**, **Modifier le relevé**, **Supprimer le relevé**. La suppression est inscrite dans la main courante.

## Fréquences par défaut

Les administrateurs règlent la liste des signaux proposés dans **Outils › Fréquences du relevé** (20 au plus).

## Résection : trouver sa position

**Outils › Résection** calcule votre position à partir de visées sur des points connus. Tous les opérateurs y ont accès.

1. Pour chaque visée (2 obligatoires, une 3e facultative), **choisissez un point connu** : recherche par nom ou indicatif, filtres « Points hauts » et « Relais » triés par distance, ou toucher la carte.
2. Notez l'**azimut mesuré**, ou utilisez **Prendre à la boussole** (téléphone ou tablette). Indiquez s'il est **Vrai** ou **Magnétique**.
3. Touchez **Calculer**.

Idéalement, les visées sont écartées d'environ 90° ; l'application prévient si elles sont trop proches.

Le résultat donne la position estimée et sa précision, avec trois boutons : **Créer un point**, **Envoyer ma position estimée** (ouvre Messages avec le texte prêt) et **Copier**.
