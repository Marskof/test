#!/bin/bash
set -e

VERSION="1.0.0"

# ==========================================
# 1. Compilation des sources Java avec Maven
# ==========================================

# Charger le JDK local s'il a été téléchargé par init_project.sh
if [ -d "$HOME/.miage-bank/jdk17" ]; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
        export JAVA_HOME="$HOME/.miage-bank/jdk17/Contents/Home"
    else
        export JAVA_HOME="$HOME/.miage-bank/jdk17"
    fi
    export PATH="$JAVA_HOME/bin:$PATH"
fi

# Vérification stricte de Java 17 (nécessaire pour Spring Boot 2.6.4)
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
    echo >&2 "ERREUR CRITIQUE : Java 17 est strictement requis pour compiler ce projet."
    echo >&2 "Veuillez lancer le script init_project.sh qui tentera de l'installer automatiquement,"
    echo >&2 "ou installez Java 17 manuellement."
    exit 1
fi

echo "Étape 1: Compilation du backend (miage-bank-back) via Maven..."
cd miage-bank-back
mvn clean package -DskipTests # compile le projet et crée un fichier .jar pour chaque micro-service
cd ..

# Choix de l'outil de build (Buildah préféré, Docker en fallback pour Mac)
if command -v buildah >/dev/null 2>&1; then
    BUILD_CMD="buildah bud"
elif command -v docker >/dev/null 2>&1; then
    echo "⚠️ Buildah non détecté (typiquement sur macOS). Utilisation de Docker en fallback pour construire les images..."
    BUILD_CMD="docker build"
else
    echo >&2 "ERREUR CRITIQUE : Ni Buildah ni Docker n'est installé. Impossible de construire les images."
    exit 1
fi

# ==========================================
# 2. Construction du Frontend
# ==========================================
echo "Etape 2: Construction du Front-end (miage-bank-front)..."
$BUILD_CMD -f ./miage-bank-front/Containerfile -t miage-bank-front:${VERSION} ./miage-bank-front

# ==========================================
# 3. Construction des micro-services (Containerfile)
# ==========================================
echo "Etape 3: Construction des micro-services Backend..."

SERVICES=("Banque-Annuaire" "Banque-ConfigServer" "Banque-ClientService" "Banque-CompteService" "Banque-CompositeService" "Banque-APIGateway") # le nom de tous les micro-services

# parcours de chaque micro-service
for SERVICE in "${SERVICES[@]}"; do
    echo "--------------------------"
    echo "Build de : $SERVICE"
    echo "--------------------------"
    
    # On se place dans le dossier du micro-service pour que la commande COPY "target/*.jar" fonctionne en local
    cd "miage-bank-back/$SERVICE"
    
    # On convertit le nom du service en minuscules (compatible avec les anciens Bash de macOS)
    SERVICE_LOWER=$(echo "$SERVICE" | tr '[:upper:]' '[:lower:]')
    
    # Buildah utilise le ContainerFile et on cible le dossier du micro-service avec le bon tag
    $BUILD_CMD -f ../../ContainerFile -t "${SERVICE_LOWER}:${VERSION}" .
    
    cd ../..
done

echo "Succès ! Tout le TP MIAGE-Bank (Backend + Frontend) est compilé."
