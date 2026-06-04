#!/bin/bash

# init_project.sh - Script automatisé pour l'évaluation du projet MIAGE Bank
# Ce script installe et configure toutes les dépendances requises pour lancer l'application.
# Il est conçu pour être sûr, idempotent (peut être relancé plusieurs fois sans casser) et optimisé pour Mac/Linux.

echo "======================================================="
echo "🚀 Démarrage de l'environnement MIAGE Bank (Evaluation)"
echo "======================================================="

# 1. Vérification et installation automatique des prérequis
echo "🔍 Vérification des prérequis locaux..."

# Docker est indispensable, on ne l'installe pas automatiquement car c'est trop intrusif
if ! command -v docker >/dev/null 2>&1; then
    echo >&2 "❌ ERREUR CRITIQUE : Docker n'est pas installé."
    echo >&2 "Docker est obligatoire pour faire tourner Minikube."
    echo >&2 "Veuillez l'installer : https://docs.docker.com/get-docker/"
    exit 1
fi

# Fonction pour vérifier et installer les outils CLI
install_if_missing() {
    local cmd=$1
    if ! command -v $cmd >/dev/null 2>&1; then
        echo "⚠️  L'outil '$cmd' n'est pas installé. Tentative d'installation automatique..."
        
        if [ "$cmd" = "kubectl" ]; then
            if [[ "$OSTYPE" == "linux-gnu"* ]]; then
                curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
                sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
                rm kubectl
            elif [[ "$OSTYPE" == "darwin"* ]]; then
                curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/darwin/amd64/kubectl"
                chmod +x ./kubectl
                sudo mv ./kubectl /usr/local/bin/kubectl
            fi
        elif [ "$cmd" = "minikube" ]; then
            if [[ "$OSTYPE" == "linux-gnu"* ]]; then
                curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
                sudo install minikube-linux-amd64 /usr/local/bin/minikube
                rm minikube-linux-amd64
            elif [[ "$OSTYPE" == "darwin"* ]]; then
                curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-darwin-amd64
                sudo install minikube-darwin-amd64 /usr/local/bin/minikube
                rm minikube-darwin-amd64
            fi
        elif [ "$cmd" = "helm" ]; then
            curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
            chmod 700 get_helm.sh
            ./get_helm.sh
            rm get_helm.sh
        fi
        
        # Vérification post-installation
        if ! command -v $cmd >/dev/null 2>&1; then
            echo >&2 "❌ Échec de l'installation automatique de $cmd. Veuillez l'installer manuellement."
            exit 1
        else
            echo "✅ $cmd a été installé avec succès."
        fi
    fi
}

# Appel de la fonction pour chaque outil
install_if_missing "kubectl"
install_if_missing "minikube"
install_if_missing "helm"

# 2. Démarrage de Minikube
echo -e "\n📦 1. Vérification / Démarrage de Minikube..."
if ! minikube status >/dev/null 2>&1; then
    echo "Minikube n'est pas lancé. Démarrage de Minikube avec l'addon Ingress..."
    minikube start --addons=ingress
else
    echo "✅ Minikube est déjà en cours d'exécution."
    # S'assurer que l'ingress est activé au cas où
    minikube addons enable ingress >/dev/null 2>&1
fi

# On s'assure que kubectl pointe bien sur minikube
kubectl config use-context minikube >/dev/null 2>&1

# 3. Installation de Vault
echo -e "\n🔐 2. Installation de HashiCorp Vault via Helm..."
helm repo add hashicorp https://helm.releases.hashicorp.com 2>/dev/null
helm repo update >/dev/null 2>&1

if ! helm status vault -n vault >/dev/null 2>&1; then
    helm upgrade --install vault hashicorp/vault -n vault --create-namespace --set "server.dev.enabled=true"
else
    echo "✅ Vault est déjà installé sur ce cluster."
fi

# Attente que Vault soit prêt
echo "⏳ Attente du démarrage de Vault..."
kubectl wait --for=condition=ready pod/vault-0 -n vault --timeout=120s

# Configuration de Vault
echo -e "\n⚙️ 3. Configuration de Vault (Auth Kubernetes + Secrets)..."
kubectl exec -n vault vault-0 -- sh -c '
# Activer l authentification K8s (silencieux si déjà activé)
vault auth enable kubernetes 2>/dev/null || true

# Configurer K8s auth
vault write auth/kubernetes/config \
    kubernetes_host="https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_SERVICE_PORT" >/dev/null 2>&1

# Créer la politique d acces aux secrets
vault policy write miage-policy - <<EOF
path "secret/data/miage-bank/database" {
  capabilities = ["read"]
}
EOF

# Créer le rôle lié au ServiceAccount miage-bank-sa
vault write auth/kubernetes/role/miage-bank-role \
    bound_service_account_names=miage-bank-sa \
    bound_service_account_namespaces=miage-bank \
    policies=miage-policy \
    ttl=1h >/dev/null 2>&1

# Injecter les secrets dans le KV
vault kv put secret/miage-bank/database \
    mysql_db=bank_db \
    mysql_password=root \
    mongo_user=admin \
    mongo_password=admin \
    mongo_db=bank_db >/dev/null 2>&1
' 
echo "✅ Secrets Vault configurés."

# 4. Installation d'External Secrets Operator
echo -e "\n🔑 4. Installation d'External Secrets Operator..."
helm repo add external-secrets https://charts.external-secrets.io 2>/dev/null
helm repo update >/dev/null 2>&1

if ! helm status external-secrets -n external-secrets >/dev/null 2>&1; then
    helm upgrade --install external-secrets external-secrets/external-secrets \
        -n external-secrets \
        --create-namespace \
        --set installCRDs=true
else
    echo "✅ External Secrets Operator est déjà installé."
fi

# 5. Installation d'ArgoCD
echo -e "\n🐙 5. Installation d'ArgoCD..."
if ! kubectl get namespace argocd >/dev/null 2>&1; then
    kubectl create namespace argocd
fi

if ! kubectl get deployment argocd-server -n argocd >/dev/null 2>&1; then
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
else
    echo "✅ ArgoCD est déjà installé sur le cluster."
fi

echo "⏳ Attente du démarrage d'ArgoCD (cela peut prendre 1 à 2 minutes)..."
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s

# 6. Déploiement de l'application via ArgoCD
echo -e "\n🚀 6. Déploiement de l'application MIAGE Bank via ArgoCD..."
kubectl apply -f argocd/application.yaml

echo "======================================================="
echo "✅ TERMINÉ ! L'environnement est en cours de déploiement par ArgoCD !"
echo "======================================================="
echo ""
echo "👉 Consultez le fichier MANUEL_UTILISATION.md pour la suite :"
echo "1. Lancez 'minikube tunnel' dans un autre terminal."
echo "2. Ajoutez '127.0.0.1 miage-bank.local' à votre fichier hosts (ex: sudo nano /etc/hosts)."
echo "3. Accédez à http://miage-bank.local"
echo ""
echo "💡 Pour surveiller l'état des pods de l'application en temps réel :"
echo "kubectl get pods -n miage-bank -w"
