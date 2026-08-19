// =============================================================================
// scenario.js — Scénario de test de charge k6 pour MicroCRM
// =============================================================================
//
// BUT
//   Solliciter l'application déployée sur Kubernetes de façon réaliste et
//   mesurable, à travers le Service exposé, afin d'observer sa tenue sous
//   différentes charges et de rendre un verdict pass/fail.
//
// STRUCTURE — deux phases, une seule mesurée
//   Le scénario enchaîne un ÉCHAUFFEMENT puis une MESURE. Les deux exercent la
//   même charge ; seule la seconde compte dans les seuils.
//
//   Ce découpage n'est pas cosmétique. Au premier appel, la JVM du backend
//   n'est pas encore chaude, les connexions ne sont pas établies et les caches
//   sont vides : inclure ces requêtes fausserait le 95e centile vers le haut et
//   ferait échouer un seuil que l'application respecte en régime établi.
//
//   Les seuils sont donc filtrés par étiquette : `{phase:mesure}`.
//
// PARCOURS SIMULÉ
//   Chaque itération reproduit ce que fait un utilisateur réel :
//     1. charge la page de l'application (bundle Angular servi par nginx)
//     2. consulte la liste des personnes    (/api/persons)
//     3. consulte la liste des organisations (/api/organizations)
//   Les appels API traversent le relais nginx puis le Service du backend :
//   c'est la chaîne complète qui est mesurée, pas un composant isolé.
//
// VARIABLES D'ENVIRONNEMENT
//   BASE_URL     URL de base            (défaut : http://192.168.49.2:30080)
//   VUS          utilisateurs virtuels  (défaut : 5)
//   DUREE        durée de mesure        (défaut : 2m)
//   ECHAUFFEMENT durée d'échauffement   (défaut : 30s)
//   PALIER       nom du palier, reporté dans le fichier de résultats
//   SEUIL_P95    seuil du 95e centile en ms (défaut : 500)
//   SEUIL_ERREUR taux d'erreur maximal      (défaut : 0.01)
//
// SEUILS — pourquoi ceux-là
//   p95 < 500 ms   : au-delà d'une demi-seconde, l'utilisateur perçoit
//                    l'attente. Le 95e centile plutôt que la moyenne, car
//                    c'est la lenteur subie par les 5 % les moins bien servis
//                    qui fait la réputation d'une application.
//   erreurs < 1 %  : une erreur sur cent est déjà visible sur un CRM utilisé
//                    quotidiennement. Ce seuil vaut pour la phase de mesure.
//
// AUTEUR   Ilyasse JAIEL — Projet 6 Expert DevOps (Option B — Orion)
// =============================================================================

import http from 'k6/http';
import { check, sleep, group } from 'k6';
import { Rate, Trend } from 'k6/metrics';

const BASE_URL = __ENV.BASE_URL || 'http://192.168.49.2:30080';
const VUS = parseInt(__ENV.VUS || '5', 10);
const DUREE = __ENV.DUREE || '2m';
const ECHAUFFEMENT = __ENV.ECHAUFFEMENT || '30s';
const PALIER = __ENV.PALIER || 'nominal';
const SEUIL_P95 = parseInt(__ENV.SEUIL_P95 || '500', 10);
const SEUIL_ERREUR = parseFloat(__ENV.SEUIL_ERREUR || '0.01');

// Métriques dédiées : elles permettent de distinguer le comportement du
// frontend (fichiers statiques) de celui de l'API (traitement applicatif).
// Une dégradation globale sans cette distinction serait ininterprétable.
const erreursFront = new Rate('erreurs_front');
const erreursApi = new Rate('erreurs_api');
const dureeFront = new Trend('duree_front', true);
const dureeApi = new Trend('duree_api', true);

export const options = {
  discardResponseBodies: false,
  scenarios: {
    echauffement: {
      executor: 'constant-vus',
      vus: VUS,
      duration: ECHAUFFEMENT,
      tags: { phase: 'echauffement' },
      gracefulStop: '5s',
    },
    mesure: {
      executor: 'constant-vus',
      vus: VUS,
      duration: DUREE,
      startTime: ECHAUFFEMENT,
      tags: { phase: 'mesure' },
      gracefulStop: '10s',
    },
  },
  thresholds: {
    // Seuls les seuils filtrés sur la phase de mesure font le verdict.
    [`http_req_duration{phase:mesure}`]: [`p(95)<${SEUIL_P95}`],
    [`http_req_failed{phase:mesure}`]: [`rate<${SEUIL_ERREUR}`],
    [`erreurs_api{phase:mesure}`]: [`rate<${SEUIL_ERREUR}`],
    // Ce seuil sert deux fins : garantir que le test a réellement émis des
    // requêtes (un test qui ne sollicite rien passerait tous les autres
    // seuils), et forcer k6 à produire la sous-métrique de débit filtrée sur
    // la phase de mesure, qui n'existerait pas sans seuil déclaré.
    [`http_reqs{phase:mesure}`]: ['count>0'],
  },
  summaryTrendStats: ['avg', 'min', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
  noConnectionReuse: false,
  userAgent: `k6-orion-charge/${PALIER}`,
};

export default function () {
  group('page applicative', function () {
    const reponse = http.get(`${BASE_URL}/`, { tags: { cible: 'front' } });
    const ok = check(reponse, {
      'front : statut 200': (r) => r.status === 200,
      'front : contenu HTML': (r) => String(r.body || '').includes('<'),
    });
    erreursFront.add(!ok);
    dureeFront.add(reponse.timings.duration);
  });

  group('api personnes', function () {
    const reponse = http.get(`${BASE_URL}/api/persons`, { tags: { cible: 'api' } });
    const ok = check(reponse, {
      'persons : statut 200': (r) => r.status === 200,
      'persons : charge utile JSON': (r) => String(r.body || '').includes('_embedded'),
    });
    erreursApi.add(!ok);
    dureeApi.add(reponse.timings.duration);
  });

  group('api organisations', function () {
    const reponse = http.get(`${BASE_URL}/api/organizations`, { tags: { cible: 'api' } });
    const ok = check(reponse, {
      'organizations : statut 200': (r) => r.status === 200,
    });
    erreursApi.add(!ok);
    dureeApi.add(reponse.timings.duration);
  });

  // Temps de réflexion : sans lui, k6 produirait une rafale continue qui ne
  // ressemble à aucun usage réel et saturerait la mesure elle-même.
  sleep(1);
}

// Écrit le résumé au format JSON, exploitable par scripts/test-charge.sh, en
// plus de l'affichage console habituel.
export function handleSummary(donnees) {
  const chemin = `/resultats/resultats-${PALIER}.json`;
  const enrichi = {
    palier: PALIER,
    parametres: {
      utilisateurs_virtuels: VUS,
      duree_mesure: DUREE,
      duree_echauffement: ECHAUFFEMENT,
      base_url: BASE_URL,
      seuil_p95_ms: SEUIL_P95,
      seuil_erreur: SEUIL_ERREUR,
    },
    horodatage: new Date().toISOString(),
    ...donnees,
  };
  const sortie = {};
  sortie[chemin] = JSON.stringify(enrichi, null, 2);
  sortie.stdout = resumeTexte(enrichi);
  return sortie;
}

const SAUT_DE_LIGNE = String.fromCharCode(10);

function resumeTexte(donnees) {
  // Les métriques k6 exposent leurs valeurs sous « values », et les
  // sous-métriques filtrées portent l'étiquette dans leur NOM. On lit donc
  // « http_req_duration{phase:mesure} » et non « http_req_duration » : cette
  // dernière inclurait l'échauffement, dont le démarrage à froid de la JVM
  // écrase les centiles.
  const m = donnees.metrics || {};
  const v = (nom) => (m[nom] || {}).values || {};

  const dureeMesure = v('http_req_duration{phase:mesure}');
  const dureeGlobale = v('http_req_duration');
  const echecs = v('http_req_failed{phase:mesure}');
  const requetes = v('http_reqs{phase:mesure}');

  return [
    '',
    `===== PALIER « ${donnees.palier} » — phase de mesure =====`,
    `  utilisateurs virtuels : ${donnees.parametres.utilisateurs_virtuels}`,
    `  requêtes mesurées     : ${(requetes.count || 0).toFixed(0)}`,
    `  débit                 : ${(requetes.rate || 0).toFixed(2)} req/s`,
    `  p50 / p95 / p99       : ${fmt(dureeMesure.med)} / ${fmt(dureeMesure['p(95)'])} / ${fmt(dureeMesure['p(99)'])}`,
    `  maximum               : ${fmt(dureeMesure.max)}`,
    `  taux d'erreur         : ${((echecs.rate || 0) * 100).toFixed(2)} %`,
    '',
    `  (pour comparaison, p95 échauffement inclus : ${fmt(dureeGlobale['p(95)'])})`,
    '',
  ].join(SAUT_DE_LIGNE);
}

function fmt(valeur) {
  return valeur === undefined || valeur === null ? 'n/d' : `${valeur.toFixed(1)} ms`;
}
