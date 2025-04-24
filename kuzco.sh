#!/bin/bash

clear
echo "=================================================="
echo " 🚀 Powered by DirekturCrypto"
echo " Inference Installer & Kuzco Node Manager"
echo " Contact us: Telegram @direkturcrypto | X @direkturcrypto"
echo "=================================================="
echo ""

# ===== CHECK & INSTALL LSOF IF MISSING =====
if ! command -v lsof &>/dev/null; then
    echo "🔧 lsof is not installed. Installing now..."
    apt-get update
    apt-get install lsof -y
else
    echo "✅ lsof is already installed."
fi

# ===== CHECK VIKEY-INFERENCE VIA PORT 14444 =====
echo "🔍 Checking if port 14444 is active..."
if lsof -i :14444 &>/dev/null; then
    echo "✅ vikey-inference is already running on port 14444."
else
    echo "❌ vikey-inference is not installed or not running. Proceeding with installation..."

    git clone https://github.com/direkturcrypto/vikey-inference
    cd vikey-inference || exit

    echo ""
    echo "🔐 Enter your VIKEY_API_KEY:"
    read -rp "VIKEY_API_KEY: " VIKEY_API_KEY

    cat >.env <<EOF
VIKEY_API_KEY=$VIKEY_API_KEY
NODE_PORT=14444
LLAMAEDGE_ENABLED=true
EOF

    chmod +x ./install.sh
    ./install.sh
    service vikey-inference restart
    cd ..
fi

# ===== CHECK FOR DOCKER =====
echo ""
echo "🐳 Checking Docker installation..."
if ! command -v docker &>/dev/null; then
    echo "🔧 Docker is not installed. Installing..."
    apt-get update
    apt-get install docker.io docker-compose -y
else
    echo "✅ Docker is already installed."
fi

# ===== USER INPUT FOR NODE SETUP =====
echo ""
read -rp "🔥 How many nodes would you like to set up? " NODE_COUNT
read -rp "🔑 Enter your WORKER_ID (from Kuzco dashboard): " WORKER_ID
read -rp "🔑 Enter your WORKER_CODE (from Kuzco dashboard): " WORKER_CODE

# ===== CLONE KUZCO INSTALLER REPO =====
if [ ! -d "kuzco-installer-docker" ]; then
    git clone https://github.com/direkturcrypto/kuzco-installer-docker
fi

# ===== CREATE DOCKER NETWORK IF NOT EXISTS =====
echo ""
echo "🌐 Checking & creating docker network: kuzco-network..."
if ! docker network ls | grep -q "kuzco-network"; then
    docker network create --subnet=10.172.1.0/24 kuzco-network
else
    echo "✅ Docker network kuzco-network already exists."
fi

# ===== CONFIGURE kuzco-main =====
cd kuzco-installer-docker || exit

cd kuzco-main || exit

# ===== Replace YOUR_VPS_IP in nginx.conf =====
GATEWAY_IP="10.172.1.1"
if grep -q "YOUR_VPS_IP" nginx.conf; then
    sed -i "s/YOUR_VPS_IP/$GATEWAY_IP/g" nginx.conf
    echo "✅ Replaced YOUR_VPS_IP with $GATEWAY_IP in nginx.conf"
fi

# ===== Inject WORKER_ID and WORKER_CODE into docker-compose.yml =====
if grep -q "KUZCO_WORKER" docker-compose.yml; then
    sed -i "s/KUZCO_WORKER=.*/YOUR_WORKER_ID=$WORKER_ID/" docker-compose.yml
else
    echo "    environment:" >> docker-compose.yml
    echo "      - KUZCO_WORKER=$WORKER_ID" >> docker-compose.yml
fi

if grep -q "KUZCO_CODE" docker-compose.yml; then
    sed -i "s/KUZCO_CODE=.*/KUZCO_CODE=$WORKER_CODE/" docker-compose.yml
else
    echo "      - KUZCO_CODE=$WORKER_CODE" >> docker-compose.yml
fi

cd ..

# ===== RUN SETUP =====
chmod +x ./kuzco-manager.sh
./kuzco-manager.sh setup --count "$NODE_COUNT" --start-from-id 1
cd kuzco-installer-docker

# ===== DONE MESSAGE =====
echo ""
echo "🎉 Setup complete!"
echo "=================================================="
echo "📦 KUZCO NODE MANAGER USAGE"
echo "--------------------------------------------------"
echo "▶️ To start nodes:    ./kuzco-manager.sh start 1-$NODE_COUNT"
echo "⏸ To stop nodes:     ./kuzco-manager.sh stop 1-$NODE_COUNT"
echo "🔁 To restart nodes:  ./kuzco-manager.sh restart 1-$NODE_COUNT"
echo "--------------------------------------------------"
echo "🔍 To check node status: ./kuzco-manager.sh status 1-$NODE_COUNT"
echo "--------------------------------------------------"
echo "🚀 Powered by DirekturCrypto"
echo "📬 Telegram: @direkturcrypto | X: @direkturcrypto"
echo "=================================================="
