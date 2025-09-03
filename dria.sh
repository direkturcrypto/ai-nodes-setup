#!/bin/bash

set -e

echo "🛠️ Starting setup...  (powered by direkturcrypto)"

### 0. Ask for VIKEY_API_KEY early
echo -n "🔐 Enter your VIKEY_API_KEY: "
read -r VIKEY_API_KEY
if [ -z "$VIKEY_API_KEY" ]; then
  echo "❌ VIKEY_API_KEY cannot be empty. Aborting."
  exit 1
fi

### 1. Install dependencies
echo "📦 Installing dependencies (docker, docker-compose, nodejs, npm, pm2, curl, git, jq, nano)..."
sudo apt update -y
sudo apt install -y curl git nano jq

# Install Docker
if ! command -v docker &> /dev/null; then
    echo "🐳 Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    sudo usermod -aG docker "$USER" || true
    echo "ℹ️ If this is your first Docker install, you may need to log out/in for group changes to apply."
else
    echo "✅ Docker already installed."
fi

# Install Docker Compose (plugin or standalone)
if ! command -v docker-compose &> /dev/null; then
    echo "🐳 Installing Docker Compose..."
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
      -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
else
    echo "✅ docker-compose already installed."
fi

# Install Node.js + npm latest
echo "📦 Installing Node.js + npm..."
curl -fsSL https://deb.nodesource.com/setup_current.x | sudo -E bash -
sudo apt install -y nodejs
sudo npm install -g npm pm2
echo "✅ Dependencies installed!"

### 2. Setup Vikey
echo "🔑 Setting up Vikey..."
cd ~/
if [ ! -d "vikey-inference" ]; then
    git clone https://github.com/direkturcrypto/vikey-inference
fi
cd vikey-inference

# Ensure binary is executable if present
if [ -f "./vikey-inference-linux" ]; then
  chmod +x ./vikey-inference-linux || true
fi

cat > .env <<EOF
# Vikey Inference Configuration
NODE_PORT=14441
DEFAULT_MODEL=llama-3.2-3b-instruct
VIKEY_API_KEY=${VIKEY_API_KEY}
EOF

# Start Vikey
nohup ./vikey-inference-linux > vikey.log 2>&1 &
sleep 3
echo "🚀 Vikey started! (logs: ~/vikey-inference/vikey.log)"

### 3. Test Vikey
echo "🔍 Testing Vikey..."
RESPONSE=$(curl -s http://localhost:14441 || true)
if [[ "$RESPONSE" == *"Endpoint not supported"* ]]; then
    echo "✅ Vikey OK → Response: ${RESPONSE}"
else
    echo "❌ Vikey test failed. Got: ${RESPONSE}"
    echo "🪵 Check logs: tail -n 200 ~/vikey-inference/vikey.log"
fi

### 4. Crypto Wallet Generator
echo "💰 Setting up crypto wallet generator..."
cd ~/
mkdir -p crypto-generator
cd crypto-generator
npm init -y > /dev/null

# Use ethers v5 (CommonJS) so require() works smoothly
npm install ethers@5 > /dev/null

cat > crypto-generator.js <<'EOF'
const fs = require('fs');
const { Wallet } = require('ethers');

const args = process.argv.slice(2);
const count = parseInt(args[0] || "1", 10);
if (isNaN(count) || count < 1) {
  console.error("Usage: node crypto-generator.js <count>");
  process.exit(1);
}

const wallets = [];
for (let i = 0; i < count; i++) {
  const w = Wallet.createRandom();
  wallets.push({
    address: w.address,
    private_key: w.privateKey
  });
}

fs.writeFileSync("wallets.json", JSON.stringify(wallets, null, 2));
console.log(`Generated ${count} wallet(s) saved in wallets.json`);
EOF

echo -n "🤔 How many wallets do you want to generate? "
read -r WALLET_COUNT
if ! [[ "$WALLET_COUNT" =~ ^[0-9]+$ ]] || [ "$WALLET_COUNT" -lt 1 ]; then
  echo "❌ Invalid number. Aborting."
  exit 1
fi

node crypto-generator.js "$WALLET_COUNT"
echo "✅ $WALLET_COUNT wallets generated in ~/crypto-generator/wallets.json"

### 5. Setup Docker Network
echo "🌐 Ensuring docker network 'dria-nodes' exists..."
if ! docker network ls | grep -q "dria-nodes"; then
    docker network create --subnet=10.172.1.0/16 dria-nodes
    echo "✅ Docker network created!"
else
    echo "ℹ️ Docker network already exists."
fi

### 6. Install Dria Nodes
echo "⚡ Setting up Dria nodes..."
cd ~/
mkdir -p dria-nodes
cd dria-nodes

WALLETS=$(cat ~/crypto-generator/wallets.json | jq -c '.[]')

i=1
for row in $WALLETS; do
  ADDR=$(echo "$row" | jq -r '.address')
  PRIV=$(echo "$row" | jq -r '.private_key')
  NODE_DIR="dria-node-$ADDR"

  mkdir -p "$NODE_DIR"
  cat > "$NODE_DIR/docker-compose.yml" <<EOF
services:
  compute_node_$i:
    image: "firstbatch/dkn-compute-node:latest"
    environment:
      RUST_LOG: \${RUST_LOG:-none,dkn_compute=info}
      # Dria
      DKN_WALLET_SECRET_KEY: $PRIV
      DKN_MODELS: llama3.3:70b-instruct-q4_K_M,llama3.1:8b-instruct-q4_K_M,llama3.2:1b-instruct-q4_K_M
      DKN_P2P_LISTEN_ADDR: /ip4/0.0.0.0/tcp/4001
      # Ollama/Vikey
      OLLAMA_HOST: http://10.172.1.1
      OLLAMA_PORT: 14441
      OLLAMA_AUTO_PULL: true
    networks:
      dria-nodes:
    restart: "on-failure"
networks:
  dria-nodes:
    external: true
EOF
  echo "📝 Node $i configured at $NODE_DIR"
  i=$((i+1))
done

### 7. Start & Restart helper
cat > manage-dria.sh <<'EOF'
#!/bin/bash
CMD=$1
case $CMD in
  start)
    echo "🚀 Starting all Dria nodes... (powered by direkturcrypto)"
    for d in dria-node-*/; do
      (cd "$d" && docker-compose up -d)
    done
    echo "✅ All nodes attempted to start."
    ;;
  restart)
    echo "♻️ Restarting all Dria nodes... (powered by direkturcrypto)"
    for d in dria-node-*/; do
      (cd "$d" && docker-compose down && docker-compose up -d)
    done
    echo "✅ All nodes attempted to restart."
    ;;
  *)
    echo "Usage: ./manage-dria.sh [start|restart]"
    ;;
esac
EOF
chmod +x manage-dria.sh

echo "✅ Dria nodes setup completed!"
echo "👉 Use ./manage-dria.sh start to run all nodes"
echo "👉 Use ./manage-dria.sh restart to restart all nodes"
echo "🙏 Credits: powered by direkturcrypto"
