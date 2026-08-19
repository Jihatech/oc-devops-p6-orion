// Capture des écrans Kibana pour les preuves du projet P6.
//
// Kibana n'expose pas d'API d'export d'image en édition « basic » : un
// navigateur sans interface est la seule voie fiable. Les captures sont ainsi
// REPRODUCTIBLES, et non le produit d'une manipulation manuelle.
//
// USAGE
//   node scripts/capturer-kibana.js                       # les deux écrans de référence
//   node scripts/capturer-kibana.js alerte-declenchee      # un écran précis
//   node scripts/capturer-kibana.js tableau-de-bord-charge alerte-declenchee
//
// ÉCRANS DISPONIBLES
//   tableau-de-bord          vue d'ensemble sur 24 h
//   regles-alerte            règles configurées et leur dernier verdict
//   tableau-de-bord-charge   vue resserrée sur 30 min, pour une campagne de charge
//   alerte-declenchee        alertes RÉELLEMENT actives
//
// VARIABLES D'ENVIRONNEMENT
//   KIBANA   URL de Kibana        (défaut : http://localhost:5601)
//   SORTIE   répertoire de sortie (défaut : répertoire courant)

const puppeteer = require('puppeteer');

const KIBANA = process.env.KIBANA || 'http://localhost:5601';
const SORTIE = process.env.SORTIE || '.';

// Les écrans sont sélectionnables par nom afin de pouvoir capturer, PENDANT
// une campagne de charge, l'état du tableau de bord et celui des alertes —
// ce qui n'a de sens qu'à cet instant précis.
const TOUS_LES_ECRANS = {
  'tableau-de-bord': {
    nom: 'kibana-tableau-de-bord.png',
    url: `${KIBANA}/app/dashboards#/view/orion-tdb-microcrm?_g=(time:(from:now-24h,to:now))`,
    attente: 25000,
    description: 'Tableau de bord MicroCRM',
  },
  'regles-alerte': {
    nom: 'kibana-regles-alerte.png',
    url: `${KIBANA}/app/management/insightsAndAlerting/triggersActions/rules`,
    attente: 18000,
    description: "Règles d'alerte",
  },
  'tableau-de-bord-charge': {
    nom: 'kibana-tableau-de-bord-sous-charge.png',
    // Fenêtre resserrée sur 30 minutes : sur 24 h, le pic de charge serait
    // écrasé par l'échelle et invisible.
    url: `${KIBANA}/app/dashboards#/view/orion-tdb-microcrm?_g=(time:(from:now-30m,to:now),refreshInterval:(pause:!f,value:10000))`,
    attente: 25000,
    description: 'Tableau de bord pendant la charge',
  },
  'alerte-declenchee': {
    nom: 'kibana-alerte-declenchee.png',
    // Vue des alertes actives : c'est ici qu'apparaît une règle réellement
    // déclenchée, par opposition à une règle simplement configurée.
    url: `${KIBANA}/app/management/insightsAndAlerting/triggersActions/alerts`,
    attente: 20000,
    description: 'Alertes déclenchées',
  },
};

// Sans argument, on capture les deux écrans de référence.
const demandes = process.argv.slice(2).filter((a) => !a.startsWith('-'));
const ECRANS = (demandes.length ? demandes : ['tableau-de-bord', 'regles-alerte'])
  .map((cle) => {
    const ecran = TOUS_LES_ECRANS[cle];
    if (!ecran) {
      console.error(`  ✖ écran inconnu : ${cle} (connus : ${Object.keys(TOUS_LES_ECRANS).join(', ')})`);
      process.exitCode = 1;
    }
    return ecran;
  })
  .filter(Boolean);

(async () => {
  const navigateur = await puppeteer.launch({
    headless: 'new',
    args: ['--no-sandbox', '--disable-dev-shm-usage'],
    defaultViewport: { width: 1680, height: 1050 },
  });

  for (const ecran of ECRANS) {
    const page = await navigateur.newPage();
    try {
      console.log(`→ ${ecran.description} : ${ecran.url}`);
      await page.goto(ecran.url, { waitUntil: 'networkidle2', timeout: 90000 });
      // Kibana rend ses panneaux après le chargement réseau : une attente
      // fixe est plus fiable qu'un sélecteur, dont le nom change de version
      // en version.
      await new Promise((r) => setTimeout(r, ecran.attente));

      // Ferme le bandeau « Your data is not secure » d'Elastic : il recouvre
      // une partie des panneaux et n'a rien à faire sur une preuve.
      await page.evaluate(() => {
        const boutons = Array.from(document.querySelectorAll('button'));
        const fermer = boutons.find((b) => /dismiss/i.test(b.textContent || ''));
        if (fermer) fermer.click();
      });
      await new Promise((r) => setTimeout(r, 2500));
      await page.screenshot({ path: `${SORTIE}/${ecran.nom}`, fullPage: false });
      console.log(`  ✔ ${ecran.nom}`);
    } catch (err) {
      console.error(`  ✖ ${ecran.nom} : ${err.message}`);
    } finally {
      await page.close();
    }
  }

  await navigateur.close();
})();
