# 08 — Matière du rapport de performance

> **Projet** : P6 « Gérez une démarche DevOps » — Option B (scénario Orion)
> **Auteur** : Ilyasse JAIEL — Expert DevOps
> **Destinataire** : Maria, CTO, et la direction d'Orion — **audience non technique**
> **Objet** : rassembler les mesures, les gains et les recommandations qui alimenteront le rapport
> de performance officiel.
>
> **Accessibilité** : structure de titres hiérarchisée, tableaux simples sans cellules fusionnées,
> aucune information portée par la seule couleur (exigence PSH du guide mentor).

---

## Sommaire

1. [Synthèse pour la direction](#1-synthèse-pour-la-direction)
2. [Le problème de départ](#2-le-problème-de-départ)
3. [Comparaison avant / après](#3-comparaison-avant--après)
4. [Gains rapportés aux objectifs d'Orion](#4-gains-rapportés-aux-objectifs-dorion)
5. [Les indicateurs DORA](#5-les-indicateurs-dora)
6. [Résultats des tests et couverture](#6-résultats-des-tests-et-couverture)
7. [Sécurité : ce qui a été trouvé et corrigé](#7-sécurité--ce-qui-a-été-trouvé-et-corrigé)
8. [Retours d'expérience exploités](#8-retours-dexpérience-exploités)
9. [Recommandations d'amélioration continue](#9-recommandations-damélioration-continue)

---

## 1. Synthèse pour la direction

En une phrase : **Orion disposait d'une chaîne qui vérifiait le code mais ne livrait rien ; elle
dispose désormais d'une chaîne qui produit, contrôle, publie, déploie et sait revenir en arrière.**

Les cinq chiffres à retenir :

| Ce qui change | Avant | Après |
|---|---|---|
| Contrôles de sécurité automatisés | **0** | **5** |
| Délai de détection d'une vulnérabilité | Plusieurs jours | **Quelques minutes** |
| Vulnérabilités dans les images livrées | **86** | **0** |
| Retour à la version précédente | Impossible | **18 secondes, sans interruption** |
| Versions livrées identifiables | Non | **5 releases tracées** |

---

## 2. Le problème de départ

L'audit initial, mené à partir des sondages des équipes Dev et Ops et de l'analyse du code, a
identifié un point de rupture **déjà éprouvé**.

Les deux sondages décrivent le même événement, vu de chaque côté :

- l'équipe Dev signale que des vulnérabilités présentes dans une image ont **retardé le premier
  déploiement** ;
- l'équipe Ops cite comme irritant principal les « retours à l'envoyeur » et demande une analyse de
  sécurité **en amont**.

La cause n'était pas l'absence d'outil : l'équipe Ops utilisait déjà Trivy. **La sécurité était
simplement placée au mauvais endroit** — en aval, à la main, après transmission de l'image.

C'est ce constat qui a orienté tout le projet : il ne s'agissait pas d'introduire la sécurité chez
Orion, mais de la **déplacer au bon moment du cycle**.

---

## 3. Comparaison avant / après

### 3.1 Chaîne d'intégration et de livraison

| Élément | Avant | Après |
|---|---|---|
| Étapes du pipeline | 2 (test, build) | **5** (lint, build, test, sécurité, package) |
| Jobs exécutés | 4 | **13** |
| Durée d'une exécution complète | Non mesurée | **environ 7 minutes** |
| Analyse statique du code | Aucune | SonarQube, porte bloquante |
| Analyse des dépendances | Aucune | npm audit et Trivy |
| Recherche de secrets versionnés | Aucune | Trivy, blocage inconditionnel |
| Analyse des images | Manuelle, après livraison | **Automatique, avant publication** |
| Images produites par la chaîne | 0 — construites à la main | **2, publiées automatiquement** |
| Artefacts conservés | Aucun | Bundle, JAR, rapports, preuves |
| Reproductibilité | Images de base flottantes | **Tout épinglé, y compris par empreinte** |

### 3.2 Livraison et exploitation

| Élément | Avant | Après |
|---|---|---|
| Numérotation des versions | `0.0.1-SNAPSHOT` figé | **Versions sémantiques automatiques** |
| Journal des versions | Aucun | Généré automatiquement |
| Transmission de version | Par courriel | Registre d'images |
| Déploiement | Manuel, commandes Docker | **Helm, automatisé et vérifié** |
| Retour arrière | Inexistant | **18 secondes, vérifié** |
| Sauvegarde | Inexistante | Automatisée, avec empreinte et manifeste |
| Restauration | Inexistante | **Testée à chaque exécution du pipeline** |
| Migrations de schéma | Aucune procédure | Job dédié, exécuté **avant** le déploiement |

### 3.3 Qualité et sécurité

| Mesure | Avant | Après |
|---|---|---|
| Couverture de tests | Non mesurée | **37,4 %** (backend 65,9 %, frontend 30,8 %) |
| Tests automatisés | 10, sans rapport exploitable | 10 applicatifs **plus 31 tests de scripts** |
| Anomalies SonarQube | Non mesurées | **2 corrigées, 0 restante** |
| Note de fiabilité | Non mesurée | **A** (partie de C) |
| Note de sécurité | Non mesurée | **A** |
| Vulnérabilités des images | 86 | **0** |
| Vulnérabilités des dépendances | 88, dont 3 critiques | 53, dont **0 critique en production** |
| Couverture OWASP Top 10 | 0 sur 10 | **7 couverts, 3 documentés** |

### 3.4 Observabilité

| Élément | Avant | Après |
|---|---|---|
| Journaux centralisés | Aucun | **375 documents indexés**, ventilés par composant |
| Format des journaux | Texte non exploitable | **JSON structuré**, agrégeable |
| Tableaux de bord | Aucun | 1 tableau de bord, 5 visualisations |
| Alertes | Aucune | **3 règles actives** |
| Mesure de la performance de livraison | Aucune | **4 indicateurs DORA** |

---

## 4. Gains rapportés aux objectifs d'Orion

Le guide mentor identifie trois objectifs : **qualité du code**, **réduction des délais**,
**collaboration**. Chaque gain est rattaché à l'un d'eux.

### 4.1 Qualité du code

| Gain | Mesure |
|---|---|
| Analyse statique systématique, bloquante | SonarQube à chaque exécution |
| Anomalies détectées puis corrigées | 2 anomalies, note de fiabilité de C à A |
| Mauvaises pratiques détectées | 13 défauts remontés par ESLint dès la première exécution |
| Couverture enfin mesurée | 37,4 %, suivie dans le temps |
| Scripts d'exploitation testés | 31 tests unitaires |

> L'équipe Dev demandait dans son sondage « des outils d'analyse statique pour éviter d'intégrer de
> mauvaises pratiques ». Cette demande est satisfaite, et elle était fondée : 13 défauts réels ont
> été trouvés dès la première exécution.

### 4.2 Réduction des délais

| Gain | Avant | Après |
|---|---|---|
| Détection d'une vulnérabilité | Après transmission à l'Ops, plusieurs jours | **Quelques minutes** |
| Construction et publication des images | Manuelles | Automatiques, environ 2 minutes |
| Déploiement | Manuel, deux personnes mobilisées | Une commande |
| Retour arrière | Impossible | **18 secondes** |
| Numérotation de version | Échange par courriel | Automatique |

### 4.3 Collaboration

| Gain | Effet |
|---|---|
| Échec de pipeline transformé en **issue de suivi** | L'incident devient un objet daté et assigné, au lieu d'un courriel |
| Synthèse automatique à chaque exécution | Les deux équipes voient le même état, au même moment |
| Documentation versionnée avec le code | Les décisions et leurs motifs restent accessibles |
| Preuves d'exécution conservées | Rollback, migrations, analyses : consultables sans redemander |
| Parité poste et chaîne d'intégration | Un développeur reproduit exactement le comportement de la chaîne |

> Le sondage Ops décrivait des échanges limités au courriel et à l'oral, sans historique. La
> traçabilité remplace désormais la mémoire des personnes.

---

## 5. Les indicateurs DORA

### 5.1 Ce que mesure chaque indicateur

| Indicateur | Ce qu'il mesure, en clair |
|---|---|
| **Fréquence de déploiement** | À quelle cadence l'équipe met une nouveauté à disposition |
| **Délai de livraison** | Combien de temps une modification met à être livrée |
| **Taux d'échec des changements** | Quelle proportion des livraisons se passe mal |
| **Délai de rétablissement** | Combien de temps il faut pour revenir à un état sain |

Les deux premiers mesurent la **vitesse**, les deux derniers la **stabilité**. Un bon dispositif
améliore les deux ensemble : aller vite en cassant tout n'est pas une performance.

### 5.2 Valeurs mesurées

Calculées sur l'historique réel du dépôt : 18 exécutions, 5 releases, 45 commits.

| Indicateur | Valeur | Niveau | Lecture |
|---|---|---|---|
| Délai de livraison | **36,7 heures** | Élevé | Une modification est livrée en moins de deux jours |
| Délai de rétablissement | **7 minutes** | Excellent | Le retour à un état sain est rapide |
| Taux d'échec | **44,4 %** | Faible | À interpréter, voir ci-dessous |
| Fréquence de déploiement | 12,7 par semaine | **Non représentatif** | Période d'observation trop courte |

### 5.3 Les deux chiffres qui demandent une explication

**Le taux d'échec de 44,4 % est réel, et il était attendu.** Les 18 exécutions analysées couvrent la
**construction** de la chaîne elle-même, pas son exploitation. Les échecs sont ceux du travail
d'ingénierie : un bit de permission manquant, une option d'outil erronée, un verrou de dépendances
incompatible. Chacun a été corrigé **et transformé en garde-fou permanent**.

Aucun de ces échecs ne correspond à un changement applicatif ayant échoué en production — situation
que cet indicateur vise normalement. **Ce chiffre est une ligne de base, pas un verdict** : il
devient significatif à partir du moment où la chaîne est stable, ce qui est l'état atteint
aujourd'hui.

**La fréquence de déploiement n'est volontairement pas notée.** Le calcul donne 12,7 déploiements par
semaine, ce qui placerait Orion au meilleur niveau. Mais la période observée ne couvre que 1,65 jour :
diviser cinq releases par un jour et demi produit un nombre exact et dépourvu de sens.

L'outil de mesure refuse donc d'attribuer un niveau en dessous de quatorze jours d'observation. La
valeur reste affichée — masquer une mesure serait pire que la nuancer — mais elle est explicitement
signalée comme non représentative.

> Ce garde-fou a été ajouté après un premier calcul qui annonçait **236 déploiements par semaine**.
> Le chiffre était mathématiquement juste et complètement faux. Un outil qui produit un nombre ne
> garantit pas que ce nombre veuille dire quelque chose.

### 5.4 Comment ces indicateurs sont produits

Un script interroge l'interface de programmation de GitHub et calcule les quatre indicateurs à
partir des commits, des exécutions et des releases. Les conventions retenues sont écrites, donc
discutables : un « déploiement » est une release publiée, et non une exécution de pipeline, car
toutes les exécutions ne livrent pas.

Chaque calcul ajoute une ligne à un historique versionné. **C'est cet historique qui porte la
tendance**, seule lecture réellement utile de ces indicateurs sur la durée.

---

## 6. Résultats des tests et couverture

### 6.1 Tests exécutés

| Catégorie | Nombre | Réussite |
|---|---|---|
| Tests du frontend | 8 | 100 % |
| Tests du backend | 2 | 100 % |
| Tests des scripts d'exploitation | 31 | 100 % |
| Cycle sauvegarde puis restauration | 1 par exécution | 100 % |

### 6.2 Couverture

| Composant | Couverture |
|---|---|
| Backend | **65,9 %** |
| Frontend | **30,8 %** |
| Projet | **37,4 %** |

### 6.3 Le constat qui surprend

**La mesure contredit la perception de l'équipe.** Dans son sondage, l'équipe Dev se déclare
« Bonne » en Angular et en Karma, et « Débutante » en Java et JUnit.

Or la couverture réelle est de **30,8 % côté frontend** contre **65,9 % côté backend** : c'est
exactement l'inverse. La priorité d'amélioration n'est donc pas là où l'équipe la situait.

C'est précisément ce qu'un système de mesure sert à révéler — et cela n'aurait pas pu être découvert
autrement, puisque aucune couverture n'était collectée auparavant.

---

## 7. Sécurité : ce qui a été trouvé et corrigé

### 7.1 Vulnérabilités des images livrées

| Image | Au départ | Après réécriture | Après correctifs système |
|---|---|---|---|
| Backend | 31 | 3 | **0** |
| Frontend | 55 | 10 | **0** |

Trois décisions expliquent ce résultat, et toutes ont été prises **sur une mesure** :

1. **Montée de version du cadre applicatif** (Spring Boot), qui a supprimé 28 vulnérabilités. Le
   correctif existait dans la même version majeure : le risque de régression était faible, et les
   tests l'ont confirmé.
2. **Changement de serveur web** pour le frontend. À fonctionnalité équivalente, l'analyse des deux
   images officielles donnait 55 vulnérabilités contre 10. L'écart venait pour l'essentiel d'un
   composant interne du premier serveur, compilé avec une bibliothèque en retard.
3. **Application des correctifs système** au moment de la construction, qui a traité les 13
   vulnérabilités restantes.

> Le contrôle de sécurité n'a pas seulement bloqué des livraisons : **il a orienté un choix
> d'architecture**, sur des chiffres et non sur une préférence.

### 7.2 Vulnérabilités des dépendances

| Mesure | Avant | Après |
|---|---|---|
| Total | 88 | **53** |
| Critiques, toutes dépendances | 3 | 1 |
| Critiques en dépendances de production | — | **0** |

Deux vulnérabilités critiques ont été effectivement corrigées. La troisième concerne un outil de
construction, jamais transmis au navigateur de l'utilisateur.

### 7.3 Douze vulnérabilités explicitement acceptées

Douze vulnérabilités touchent le cadre frontend dans la version fournie. Pour chacune, le correctif
n'existe que **deux versions majeures plus loin** : les traiter suppose une migration applicative,
hors du périmètre d'une mission d'industrialisation.

Deux réponses étaient possibles :

| Option | Conséquence |
|---|---|
| Abaisser le seuil de blocage | La chaîne devient aveugle à **toute nouvelle vulnérabilité**, y compris corrigeable |
| **Accepter nommément les douze** | Le seuil reste strict ; toute nouvelle vulnérabilité bloque |

La seconde a été retenue. Chaque acceptation porte une justification et une **date de réexamen**
fixée au 30 novembre 2026. Aucune acceptation permanente n'est admise.

> C'est la différence entre **gérer** un risque et le **masquer**.

### 7.4 Un risque critique signalé, non corrigé

L'interface de programmation de l'application est **exposée sans authentification**. Les données
qu'elle manipule sont des personnes et des organisations : ce sont des données à caractère personnel,
et le risque relève du RGPD.

Ce défaut n'a **pas** été corrigé, et c'est un choix assumé : y remédier suppose de concevoir un
modèle d'autorisation, ce qui relève du développement applicatif et non de l'industrialisation de la
chaîne.

**C'est la recommandation prioritaire du volet sécurité.** Il faut noter que l'analyse statique ne
peut pas détecter ce défaut : elle signale du code dangereux, pas du code **manquant**. La chaîne a
fait ce qu'on attend d'elle en le rendant visible ; elle ne pouvait pas le corriger seule.

---

## 8. Retours d'expérience exploités

Chaque incident rencontré pendant le projet a été traité comme un retour d'expérience et a produit
un **garde-fou permanent**. C'est la réponse concrète à la question de la fiabilité et de la
traçabilité des livraisons.

| Incident | Ce qu'il a révélé | Garde-fou mis en place |
|---|---|---|
| Un fichier de lancement versionné sans droit d'exécution | Un poste Windows ne porte pas cette information ; le défaut était invisible en local | La chaîne vérifie les droits d'exécution dès la première étape, avec la commande de correction |
| Une version d'outil différente entre le poste et la chaîne | Le verdict d'un contrôle dépendait d'un composant non maîtrisé | La version de l'outil est épinglée et identique des deux côtés |
| Le contrôle de sécurité échouait **quand il ne trouvait rien** | Un comportement du shell rendait le succès indistinguable d'une erreur | Le comptage est isolé dans une fonction couverte par quatre tests |
| Une empreinte d'image inventée dans un fichier de configuration | Un identifiant plausible mais faux donne l'apparence de la rigueur | Les empreintes sont désormais résolues depuis le registre avant usage |
| Des preuves d'exécution absentes du dépôt public | Une règle d'exclusion les avait masquées ; tout paraissait normal en local | Un contrôle vérifie que chaque lien de la documentation pointe vers un fichier **réellement versionné** |
| Un calcul d'indicateur donnant un résultat aberrant | Le code était juste, la définition de la période ne l'était pas | Tout résultat portant sur moins de quatorze jours est marqué non représentatif |

**Le point commun de ces six incidents** : cinq sur six étaient **invisibles sur le poste de
développement** et n'ont été révélés que par l'automatisation. C'est l'argument le plus concret en
faveur de la démarche chez Orion, où tout est aujourd'hui exécuté à la main sur des postes.

---

## 9. Recommandations d'amélioration continue

### 9.1 Priorité haute

| Nº | Recommandation | Bénéfice attendu | Effort |
|---|---|---|---|
| 1 | **Migrer la base de données** vers un moteur persistant | Supprime la perte de données au redémarrage, permet de sauvegarder les données, rend les tests représentatifs | Moyen |
| 2 | **Ajouter une authentification** à l'interface de programmation | Traite le risque critique de sécurité et l'enjeu RGPD | Moyen |
| 3 | **Monter le cadre frontend** de deux versions majeures | Résout les douze vulnérabilités acceptées, avant leur date de réexamen | Élevé |

### 9.2 Priorité moyenne

| Nº | Recommandation | Bénéfice attendu | Effort |
|---|---|---|---|
| 4 | Porter la couverture du frontend de 30,8 % à 60 % | Comble l'écart le plus important, et le plus inattendu | Moyen |
| 5 | Externaliser les sauvegardes hors du poste | Une sauvegarde stockée sur la machine qu'elle protège ne protège de rien | Faible |
| 6 | Brancher les alertes sur un canal d'équipe | Une alerte que personne ne reçoit n'est pas une alerte | Faible |
| 7 | Déployer automatiquement vers un environnement de recette permanent | Réduit encore le délai de livraison | Moyen |

### 9.3 À envisager ensuite

| Nº | Recommandation | Prérequis |
|---|---|---|
| 8 | Analyse dynamique de sécurité sur l'application déployée | Environnement stable |
| 9 | Tests de charge | Recommandation 1 |
| 10 | Migration vers un cluster managé | Décision budgétaire, voir document 09 |

### 9.4 Ce qu'il faut surveiller en premier

Trois indicateurs méritent d'être suivis dès maintenant :

1. **Le taux d'échec**, qui doit décroître nettement maintenant que la chaîne est stabilisée. C'est
   la meilleure preuve que la démarche produit ses effets.
2. **La couverture de tests**, qui ne doit plus jamais baisser. La porte de qualité y veille sur le
   code nouveau.
3. **Le nombre de vulnérabilités acceptées**, qui doit revenir à zéro avant la date de réexamen.

---

## Documents liés

| Document | Contenu |
|---|---|
| [`01-audit-swot.md`](01-audit-swot.md) | État initial et constats détaillés |
| [`04-plan-tests.md`](04-plan-tests.md) | Stratégie de tests et seuils |
| [`05-plan-securite.md`](05-plan-securite.md) | Contrôles de sécurité et risques résiduels |
| [`docs/captures/`](captures/) | Preuves : analyses, images, rollback, ELK, DORA |
| [`09-evolution-cloud.md`](09-evolution-cloud.md) | Migration vers le cloud, étapes et coûts |
