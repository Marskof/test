#!/bin/bash
set -e

VERSION="1.0.0"

# ==========================================
# 1. Compilation des sources Java avec Maven
# ==========================================

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

# ==========================================
# 2. Construction du Frontend
# ==========================================
echo "Etape 2: Construction du Front-end (miage-bank-front)..."
buildah bud -t miage-bank-front:${VERSION} ./miage-bank-front # buildah bud est l'équivalent de docker build

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
    
    # Buildah utilise le ContainerFile et on cible le dossier du micro-service avec le bon tag
    buildah bud -f ../../ContainerFile -t "${SERVICE,,}:${VERSION}" .
    
    cd ../..
done

echo "Succès ! Tout le TP MIAGE-Bank (Backend + Frontend) est compilé."
