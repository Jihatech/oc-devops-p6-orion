// Capture des écrans Kibana pour les preuves du projet P6.
// Kibana n'expose pas d'API d'export d'image en édition « basic » : un
// navigateur sans interface est la seule voie fiable.

const puppeteer = require('puppeteer');

const KIBANA = process.env.KIBANA || 'http://localhost:5601';
const SORTIE = process.env.SORTIE || '.';

const ECRANS = [
  {
    nom: 'kibana-tableau-de-bord.png',
    url: `${KIBANA}/app/dashboards#/view/orion-tdb-microcrm?_g=(time:(from:now-24h,to:now))`,
    attente: 25000,
    description: 'Tableau de bord MicroCRM',
  },
  {
    nom: 'kibana-regles-alerte.png',
    url: `${KIBANA}/app/management/insightsAndAlerting/triggersActions/rules`,
    attente: 18000,
    description: "Règles d'alerte",
  },
];

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
