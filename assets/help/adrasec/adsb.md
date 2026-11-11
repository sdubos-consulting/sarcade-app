# ADS-B : les aéronefs

## Afficher les aéronefs

- **Outils › Avions (ADS-B)**, ou Calques › Référentiel ADRASEC › **Aéronefs**.
- Les positions viennent d'**OpenSky Network** (récepteurs bénévoles), actualisées toutes les 30 secondes environ. Le serveur n'interroge OpenSky que pendant l'affichage.
- Manquent : les aéronefs militaires et d'État, les ULM et planeurs sans ADS-B, les zones mal couvertes. **Ce n'est pas une information aéronautique officielle.**

Il faut une connexion : rien n'est gardé pour le hors connexion.

## Filtres

Les filtres restent sur cet appareil.

- **Tranches d'altitude** : Bas, Moyen, Haut (seuils de 3 000 et 10 000 ft par défaut ; « Haut » masqué au départ).
- **Avions au sol**, **Afficher les indicatifs**.
- **Tout afficher** et **Valeurs par défaut** ; le nombre d'aéronefs masqués est indiqué.
- Un aéronef en **urgence (7700, 7600, 7500)** reste toujours affiché et déclenche une alerte avec le bouton **Voir**.

## Liste et fiche

- La liste « Aéronefs entendus » met les urgences en tête, puis les aéronefs suivis, puis une section par tranche d'altitude.
- Touchez un aéronef pour sa fiche : adresse OACI, pays, altitude, catégorie, vitesse, cap, vitesse verticale, transpondeur, dernière réception. Une position de plus de 60 secondes est signalée comme ancienne.
- **Suivre** affiche sa route (30 minutes au plus). **Ne plus suivre aucun avion** arrête tous les suivis.
- La recherche de la carte trouve un aéronef par son indicatif ou son code OACI.

## Si rien ne s'affiche

- « Le serveur n'a pas d'identifiants OpenSky » : le serveur n'est pas réglé pour l'ADS-B ; voyez l'administrateur.
- Paramètres › Diagnostic, ligne « ADS-B (OpenSky) », dit par exemple si le quota est atteint ou si le service est en veille.
