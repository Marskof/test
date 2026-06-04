# Manuel d'Utilisation et de Déploiement

Ce guide détaille la procédure de déploiement et d'évaluation du projet **MIAGE Bank** en environnement local.

Afin de simplifier l'évaluation, un script d'automatisation est fourni. Il se charge de configurer intégralement l'environnement Kubernetes, d'installer les dépendances (Vault, External Secrets Operator, ArgoCD) et de déclencher la chaîne de déploiement GitOps.

## 1. Prérequis

Assurez-vous que les outils suivants sont installés sur votre poste de travail :
- **Docker** (ou équivalent)
- **Minikube**
- **kubectl**
- **Helm**

*(Note : Sous Linux et macOS, le script d'initialisation tentera d'installer automatiquement kubectl, minikube et helm s'ils sont manquants).*

## 2. Lancement Automatisé

Ouvrez un terminal (Bash, Git Bash ou WSL) à la racine de ce dossier et exécutez les commandes suivantes :

```bash
chmod +x init_project.sh
./init_project.sh
```

**Ce que fait ce script :**
1. 📦 **Démarrage de Minikube** avec l'addon `ingress` activé.
2. 🔐 **Déploiement de HashiCorp Vault** (en mode dev). Le script s'occupe de configurer l'authentification Kubernetes et d'injecter tous les secrets nécessaires (identifiants des bases de données).
3. 🔑 **Installation d'External Secrets Operator (ESO)** pour lier Vault à nos microservices.
4. 🐙 **Déploiement d'ArgoCD**, notre outil GitOps.
5. 🚀 **Déploiement de l'Application** en appliquant notre manifeste `argocd/application.yaml`. ArgoCD prend alors le relais et synchronise le dépôt pour créer l'infrastructure MIAGE Bank !

## 3. Vérification du Déploiement

À la fin du script, l'application est en cours de création. Vous pouvez observer ArgoCD monter les conteneurs (bases de données et services Java) en temps réel avec la commande :

```bash
kubectl get pods -n miage-bank -w
```
*(Patientez quelques minutes jusqu'à ce que tous les pods soient en statut `Running` ou `Completed`)*

## 4. Accès à l'Application

L'architecture intègre un Ingress Traefik répondant au nom de domaine **`miage-bank.local`**. 

1. **Activez le tunnel Minikube** (gardez ce terminal ouvert en arrière-plan) :
   ```bash
   minikube tunnel
   ```

2. **Configurez votre fichier `hosts`** :
   Pour que votre navigateur reconnaisse le domaine, ajoutez cette ligne à votre fichier `hosts` :
   `127.0.0.1 miage-bank.local`
   
   - **Sur Windows :** `C:\Windows\System32\drivers\etc\hosts` (à éditer en mode administrateur)
   - **Sur Linux / macOS :** `/etc/hosts` (via `sudo`)

3. **Visitez le site !** Rendez-vous sur votre navigateur à l'adresse : **[http://miage-bank.local](http://miage-bank.local)**

## 5. Interface d'Administration ArgoCD

Si vous souhaitez voir l'état de synchronisation GitOps sur la belle interface graphique d'ArgoCD :

1. Faites suivre le port :
   ```bash
   kubectl port-forward svc/argocd-server -n argocd 8080:443
   ```
2. Obtenez le mot de passe généré automatiquement (l'utilisateur est `admin`) :
   ```bash
   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d ; echo
   ```
3. Connectez-vous sur **[https://localhost:8080](https://localhost:8080)**.

---
*L'ensemble des choix d'architecture, l'analyse comparative Buildah/Docker et le rapport de sécurité Trivy/Dive sont détaillés dans le fichier `README.md` principal.*
