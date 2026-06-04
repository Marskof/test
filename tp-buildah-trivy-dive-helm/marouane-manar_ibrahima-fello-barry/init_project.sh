#!/bin/bash

# init_project.sh - Script automatisé pour l'évaluation du projet MIAGE Bank
# Ce script installe et configure toutes les dépendances requises pour lancer l'application.
# Il est conçu pour être sûr, idempotent (peut être relancé plusieurs fois sans casser) et optimisé pour Mac/Linux.

echo "======================================================="
echo "Démarrage de l'environnement MIAGE Bank (Évaluation)"
echo "======================================================="

# 1. Vérification et installation automatique des prérequis
echo "Vérification des prérequis locaux..."

# Docker est indispensable, on ne l'installe pas automatiquement car c'est trop intrusif
if ! command -v docker >/dev/null 2>&1; then
    echo >&2 "ERREUR CRITIQUE : Docker n'est pas installé."
    echo >&2 "Docker est obligatoire pour faire tourner Minikube."
    echo >&2 "Veuillez l'installer : https://docs.docker.com/get-docker/"
    exit 1
fi

# Charger le JDK local s'il a déjà été téléchargé lors d'une exécution précédente
if [ -d "$HOME/.miage-bank/jdk17" ]; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
        export JAVA_HOME="$HOME/.miage-bank/jdk17/Contents/Home"
    else
        export JAVA_HOME="$HOME/.miage-bank/jdk17"
    fi
    export PATH="$JAVA_HOME/bin:$PATH"
fi

# Vérification de Java 17 (nécessaire pour la compilation Maven de Spring Boot 2.6.4)
check_java() {
    if ! command -v java >/dev/null 2>&1; then return 1; fi
    local JAVA_VERSION=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}' | awk -F '.' '{print $1}')
    if [ "$JAVA_VERSION" = "1" ]; then
        JAVA_VERSION=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}' | awk -F '.' '{print $2}')
    fi
    if [ "$JAVA_VERSION" != "17" ]; then return 1; fi
    return 0
}

if ! check_java; then
    echo "Java 17 n'est pas installé ou n'est pas la version par défaut."
    echo "Tentative d'installation automatique de Java 17..."
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if command -v apt-get >/dev/null 2>&1; then
            sudo apt-get update 2>/dev/null || true
            sudo apt-get install -y openjdk-17-jdk 2>/dev/null || echo "Le paquet openjdk-17-jdk n'est pas disponible sur ce système."
            sudo update-alternatives --set java /usr/lib/jvm/java-17-openjdk-amd64/bin/java 2>/dev/null || true
            sudo update-alternatives --set javac /usr/lib/jvm/java-17-openjdk-amd64/bin/javac 2>/dev/null || true
        elif command -v dnf >/dev/null 2>&1; then
            sudo dnf install -y java-17-openjdk-devel 2>/dev/null || true
        elif command -v yum >/dev/null 2>&1; then
            sudo yum install -y java-17-openjdk-devel 2>/dev/null || true
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        if command -v brew >/dev/null 2>&1; then
            brew install openjdk@17
            # Lien symbolique nécessaire pour macOS pour enregistrer le JDK
            sudo ln -sfn $(brew --prefix openjdk@17)/libexec/openjdk.jdk /Library/Java/JavaVirtualMachines/openjdk-17.jdk 2>/dev/null || true
        fi
    fi
    
    # Si Java 17 n'est toujours pas disponible après tentative, méthode de secours universelle (téléchargement local)
    if ! check_java; then
        echo "Les gestionnaires de paquets système n'ont pas pu installer Java 17."
        echo "Téléchargement et configuration automatique d'une version locale de Java 17 (Eclipse Temurin)..."
        
        OS_TYPE="linux"
        if [[ "$OSTYPE" == "darwin"* ]]; then
            OS_TYPE="mac"
        fi
        
        ARCH_TYPE="x64"
        ARCH_RAW=$(uname -m)
        if [[ "$ARCH_RAW" == "aarch64" || "$ARCH_RAW" == "arm64" ]]; then
            ARCH_TYPE="aarch64"
        fi
        
        JDK_DIR="$HOME/.miage-bank/jdk17"
        mkdir -p "$JDK_DIR"
        
        DOWNLOAD_URL="https://api.adoptium.net/v3/binary/latest/17/ga/${OS_TYPE}/${ARCH_TYPE}/jdk/hotspot/normal/eclipse?project=jdk"
        echo "Téléchargement du JDK depuis Adoptium pour ${OS_TYPE} (${ARCH_TYPE})..."
        
        if command -v curl >/dev/null 2>&1; then
            curl -L "$DOWNLOAD_URL" -o "/tmp/jdk17.tar.gz"
        elif command -v wget >/dev/null 2>&1; then
            wget -O "/tmp/jdk17.tar.gz" "$DOWNLOAD_URL"
        else
            echo >&2 "ERREUR : curl ou wget est nécessaire pour télécharger Java 17."
            exit 1
        fi
        
        echo "Extraction de Java 17..."
        tar -xzf "/tmp/jdk17.tar.gz" -C "$JDK_DIR" --strip-components=1
        rm -f "/tmp/jdk17.tar.gz"
        
        if [[ "$OSTYPE" == "darwin"* ]]; then
            export JAVA_HOME="$JDK_DIR/Contents/Home"
        else
            export JAVA_HOME="$JDK_DIR"
        fi
        export PATH="$JAVA_HOME/bin:$PATH"
    fi
    
    if ! check_java; then
        echo >&2 "ERREUR CRITIQUE : Impossible d'installer ou de configurer Java 17 automatiquement."
        echo >&2 "Veuillez installer Java 17 manuellement car il est strictement requis."
        exit 1
    else
        echo "Java 17 a été configuré avec succès."
    fi
fi



# Fonction pour vérifier et installer les outils CLI
install_if_missing() {
    local cmd=$1
    if ! command -v $cmd >/dev/null 2>&1; then
        echo "L'outil '$cmd' n'est pas installé. Tentative d'installation automatique..."
        
        # S'assurer que le répertoire de destination existe (pour Linux / macOS)
        if [[ "$OSTYPE" == "linux-gnu"* ]] || [[ "$OSTYPE" == "darwin"* ]]; then
            sudo mkdir -p /usr/local/bin 2>/dev/null || true
        fi
        
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
            if [[ "$OSTYPE" == "linux-gnu"* ]]; then
                curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
                chmod 700 get_helm.sh
                ./get_helm.sh >/dev/null 2>&1
                rm get_helm.sh
            elif [[ "$OSTYPE" == "darwin"* ]]; then
                if command -v brew >/dev/null 2>&1; then
                    brew install helm
                fi
            fi
        elif [ "$cmd" = "mvn" ]; then
            if [[ "$OSTYPE" == "linux-gnu"* ]]; then
                if command -v apt-get >/dev/null 2>&1; then
                    sudo apt-get update 2>/dev/null || true
                    sudo apt-get install -y maven
                elif command -v dnf >/dev/null 2>&1; then
                    sudo dnf install -y maven
                elif command -v yum >/dev/null 2>&1; then
                    sudo yum install -y maven
                fi
            elif [[ "$OSTYPE" == "darwin"* ]]; then
                brew install maven
            fi
        elif [ "$cmd" = "buildah" ]; then
            if [[ "$OSTYPE" == "linux-gnu"* ]]; then
                if command -v apt-get >/dev/null 2>&1; then
                    sudo apt-get update 2>/dev/null || true
                    sudo apt-get install -y buildah
                elif command -v dnf >/dev/null 2>&1; then
                    sudo dnf install -y buildah
                elif command -v yum >/dev/null 2>&1; then
                    sudo yum install -y buildah
                fi
            elif [[ "$OSTYPE" == "darwin"* ]]; then
                echo "ℹ️  Buildah n'est pas disponible nativement sur macOS. Docker sera utilisé comme solution de repli."
                return 0 # On sort de la fonction sans erreur pour le Mac
            fi
        fi
        
        # Vérification post-installation
        if ! command -v $cmd >/dev/null 2>&1; then
            if [ "$cmd" = "buildah" ] && [[ "$OSTYPE" == "darwin"* ]]; then
                # Cas spécial déjà géré au-dessus
                true
            else
                echo >&2 "Échec de l'installation automatique de $cmd. Veuillez l'installer manuellement."
                exit 1
            fi
        else
            echo "$cmd a été installé avec succès."
        fi
    fi
}

# Appel de la fonction pour chaque outil
install_if_missing "kubectl"
install_if_missing "minikube"
install_if_missing "helm"
install_if_missing "mvn"
install_if_missing "buildah"

# 2. Démarrage de Minikube
echo -e "\n1. Vérification / Démarrage de Minikube..."
if ! minikube status >/dev/null 2>&1; then
    echo "Minikube n'est pas lancé. Démarrage de Minikube..."
    minikube start
else
    echo "Minikube est déjà en cours d'exécution."
fi

# S'assurer que l'ingress Nginx est activé
echo "Activation de l'Ingress Controller Nginx..."
minikube addons enable ingress >/dev/null 2>&1

# On s'assure que kubectl pointe bien sur minikube
kubectl config use-context minikube >/dev/null 2>&1

# Nettoyage optionnel pour garantir un environnement vierge
echo "Nettoyage de l'ancien environnement (s'il existe)..."
kubectl delete -f argocd/application.yaml --ignore-not-found=true >/dev/null 2>&1
kubectl delete namespace miage-bank --ignore-not-found=true >/dev/null 2>&1
kubectl delete namespace vault --ignore-not-found=true >/dev/null 2>&1
kubectl delete clusterrolebinding vault-server-binding --ignore-not-found=true >/dev/null 2>&1

# 2.5 Compilation et création des images OCI via Buildah (build_all.sh)
echo -e "\n2. Construction des images via Buildah et chargement dans Minikube..."

echo "Exécution de build_all.sh..."
# Corriger les retours à la ligne au cas où le script aurait été cloné sur Windows
sed -i 's/\r$//' build_all.sh 2>/dev/null || true
chmod +x build_all.sh
./build_all.sh || { echo >&2 "Erreur: L'exécution de build_all.sh a échoué."; exit 1; }

echo "Chargement des images Buildah vers Minikube..."
SERVICES=("banque-annuaire" "banque-configserver" "banque-clientservice" "banque-compteservice" "banque-compositeservice" "banque-apigateway" "miage-bank-front")
for TAG in "${SERVICES[@]}"; do
    echo "  -> Export et chargement de $TAG:1.0.0..."
    if command -v buildah >/dev/null 2>&1; then
        # Export en archive tar depuis Buildah pour être 100% sûr du transfert
        buildah push "$TAG:1.0.0" docker-archive:"$TAG.tar":"$TAG:1.0.0" >/dev/null 2>&1
        minikube image load "$TAG.tar"
        rm -f "$TAG.tar"
    elif command -v docker >/dev/null 2>&1; then
        # Fallback pour macOS
        docker save "$TAG:1.0.0" -o "$TAG.tar" >/dev/null 2>&1
        minikube image load "$TAG.tar"
        rm -f "$TAG.tar"
    else
        echo >&2 "ERREUR : Impossible d'exporter l'image $TAG, ni buildah ni docker n'est installé."
        exit 1
    fi
done

echo "Toutes les images sont prêtes dans Minikube."

# 3. Installation de Vault
echo -e "\n3. Installation de HashiCorp Vault via Helm..."
helm repo add hashicorp https://helm.releases.hashicorp.com 2>/dev/null
helm repo update >/dev/null 2>&1

if ! helm status vault -n vault >/dev/null 2>&1; then
    # Supprimer d'éventuels restes conflictuels d'une précédente installation de Vault
    helm uninstall vault -n default >/dev/null 2>&1 || true
    kubectl delete clusterrole vault-agent-injector-clusterrole --ignore-not-found=true >/dev/null 2>&1
    kubectl delete clusterrolebinding vault-agent-injector-binding --ignore-not-found=true >/dev/null 2>&1
    
    helm upgrade --install vault hashicorp/vault -n vault --create-namespace --set "server.dev.enabled=true"
else
    echo "Vault est déjà installé sur ce cluster."
fi

# Attente que Vault soit prêt
echo "Attente du démarrage de Vault..."
sleep 5 # Attendre que le pod soit créé par le StatefulSet
kubectl wait --for=condition=ready pod/vault-0 -n vault --timeout=120s
sleep 5 # Laisser le temps à l'API Vault de démarrer en interne

# Configuration de Vault
echo -e "\n4. Configuration de Vault (Auth Kubernetes + Secrets)..."
kubectl exec -n vault vault-0 -- sh -c '
# Activer l authentification K8s (silencieux si déjà activé)
vault auth enable kubernetes || echo "Auth déjà activé"

# Configurer K8s auth
vault write auth/kubernetes/config \
    kubernetes_host="https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_SERVICE_PORT"

# Créer la politique d acces aux secrets
echo "path \"secret/data/miage-bank/database\" { capabilities = [\"read\"] }" | vault policy write miage-policy -

# Créer le rôle lié au ServiceAccount miage-bank-app-sa
vault write auth/kubernetes/role/miage-bank-role \
    bound_service_account_names=miage-bank-app-sa \
    bound_service_account_namespaces=miage-bank \
    policies=miage-policy \
    ttl=1h

# Injecter les secrets dans le KV
vault kv put secret/miage-bank/database \
    mysql_db=bank_db \
    mysql_password=root \
    mongo_user=admin \
    mongo_password=admin \
    mongo_db=bank_db >/dev/null 2>&1
' 
echo "Secrets Vault configurés."

# 4. Installation d'External Secrets Operator
echo -e "\n5. Installation d'External Secrets Operator..."
helm repo add external-secrets https://charts.external-secrets.io 2>/dev/null
helm repo update >/dev/null 2>&1

if ! helm status external-secrets -n external-secrets >/dev/null 2>&1; then
    helm upgrade --install external-secrets external-secrets/external-secrets \
        -n external-secrets \
        --create-namespace \
        --set installCRDs=true
else
    echo "External Secrets Operator est déjà installé."
fi

# 5. Installation d'ArgoCD
echo -e "\n6. Installation d'ArgoCD..."
if ! kubectl get namespace argocd >/dev/null 2>&1; then
    kubectl create namespace argocd
fi

if ! kubectl get deployment argocd-server -n argocd >/dev/null 2>&1; then
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml --server-side=true
else
    echo "ArgoCD est déjà installé sur le cluster."
fi

echo "Attente du démarrage d'ArgoCD (cela peut prendre 1 à 2 minutes)..."
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s
kubectl wait --for=condition=available deployment/argocd-repo-server -n argocd --timeout=300s
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-application-controller -n argocd --timeout=300s

# 6. Déploiement de l'application via ArgoCD
echo -e "\n7. Déploiement de l'application MIAGE Bank via ArgoCD..."
kubectl apply -f argocd/application.yaml

echo "======================================================="
echo "TERMINÉ : L'environnement est en cours de déploiement par ArgoCD."
echo "======================================================="
echo ""
echo "Consultez le fichier MANUEL_UTILISATION.md pour la suite :"
echo "1. Lancez 'minikube tunnel' dans un autre terminal."
echo "2. Ajoutez '127.0.0.1 miage-bank.local' à votre fichier hosts (ex: sudo nano /etc/hosts)."
echo "3. Accédez à http://miage-bank.local"
echo ""
echo "Pour surveiller l'état des pods de l'application en temps réel :"
echo "kubectl get pods -n miage-bank -w"
