// URL de base de l'API MicroCRM.
//
// Modifié (P6) : la valeur d'origine était « http://localhost:8080 », codée en
// dur. Ce choix fonctionne sur un poste de développement mais rend
// l'application INDÉPLOYABLE ailleurs : le navigateur de l'utilisateur
// résoudrait « localhost » vers sa propre machine, pas vers le serveur.
//
// La valeur est désormais un chemin RELATIF. Le serveur qui sert le frontend
// (Caddy) relaie « /api/* » vers le backend — voir app/misc/docker/Caddyfile.
// L'application devient ainsi indépendante de son environnement : la même
// image fonctionne en local, sur Minikube et sur un cluster managé, sans
// reconstruction ni variable d'environnement.
export const API_BASE_URL = "/api"
