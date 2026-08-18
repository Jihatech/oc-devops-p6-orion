# Indicateurs DORA — MicroCRM (Orion)

> Calculés le **2026-08-18T19:27:59Z** sur les **90 derniers jours**,
> à partir de l'historique réel du dépôt `Jihatech/oc-devops-p6-orion` (branche `main`).
> Volumétrie analysée : 18 exécutions de pipeline, 3 releases, 45 commits.

## Synthèse

| Indicateur | Valeur | Niveau DORA | Référence du niveau |
|---|---|---|---|
| **Fréquence de déploiement** | 12.71 / semaine | ⚪ n/d | periode d'observation trop courte (1.7 j) pour un taux hebdomadaire |
| **Délai de livraison** (médiane) | 36.7 h | 🟢 High | moins d'une semaine |
| **Taux d'échec des changements** | 44.4 % | 🔴 Low | plus de 15 % |
| **Délai de rétablissement** (médiane) | 7 min | 🟢 Elite | moins d'une heure |

## Détail des calculs

### Fréquence de déploiement

- **3 déploiements** sur 1.65 jours observés
- soit **12.71 par semaine** (1.82 par jour)

> Un « déploiement » est une **release publiée par semantic-release**, seul événement
> produisant un artefact versionné, immuable et promu. Compter les exécutions de pipeline
> gonflerait la fréquence, puisque toutes ne livrent rien.

### Délai de livraison (lead time for changes)

- **45 commits livrés**, 0 pas encore livrés
- médiane **36.7 h** · moyenne 22.5 h
- amplitude : de 0 min à 37.5 h

> La **médiane** est retenue plutôt que la moyenne : un commit ancien repris tardivement
> décalerait la moyenne sans rien dire du flux réel.

### Taux d'échec des changements

- **8 échecs** sur 18 exécutions terminées
- soit **44.4 %**

### Délai de rétablissement (MTTR)

- **4 incidents** résolus
- médiane **7 min** · maximum 28 min

> Les échecs consécutifs comptent pour **un seul incident** : la chaîne reste indisponible
> tant qu'aucune exécution n'a réussi.

#### Incidents et rétablissements

| Échec | Rétablissement | Durée |
|---|---|---|
| 2026-08-17T04:19:58Z | 2026-08-17T04:24:10Z | 4 min |
| 2026-08-17T04:27:34Z | 2026-08-17T04:30:48Z | 3 min |
| 2026-08-18T01:38:54Z | 2026-08-18T02:06:46Z | 28 min |
| 2026-08-18T17:03:32Z | 2026-08-18T17:12:55Z | 10 min |

---

<sub>Généré par `scripts/dora-metrics.py` à partir de l'API GitHub. Les seuils de niveau
proviennent du rapport public « Accelerate State of DevOps » et servent à SITUER un
résultat, non à le juger : ils doivent être lus avec le contexte du projet.</sub>
