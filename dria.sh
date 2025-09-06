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
echo "📦 Checking dependencies (docker, nodejs, npm, pm2, curl, git, jq, nano)..."

NEED_UPDATE=false

install_if_missing() {
  PKG=$1
  CMD=$2
  if ! command -v $CMD &>/dev/null; then
    echo "📥 Installing $PKG..."
    NEED_UPDATE=true
    sudo apt install -y $PKG
  else
    echo "✅ $PKG already installed."
  fi
}

# Basic tools
install_if_missing "curl" curl
install_if_missing "git" git
install_if_missing "nano" nano
install_if_missing "jq" jq
install_if_missing "vim" vim

# Run apt update only if needed
if $NEED_UPDATE; then
  echo "🔄 Running apt update once..."
  sudo apt update -y
fi

# Docker
if ! command -v docker &>/dev/null; then
  echo "🐳 Installing Docker..."
  sudo apt-get install -y docker docker-compose
  sudo usermod -aG docker "$USER" || true
  echo "ℹ️ If this is your first Docker install, log out/in to apply group changes."
else
  echo "✅ Docker already installed."
fi

# Node.js + npm
if ! command -v node &>/dev/null; then
  echo "📥 Installing Node.js + npm..."
  curl -fsSL https://deb.nodesource.com/setup_current.x | sudo -E bash -
  sudo apt install -y nodejs
else
  echo "✅ Node.js already installed (version $(node -v))."
fi

# n & pm2
if ! command -v n &>/dev/null; then
  echo "📥 Installing n (Node version manager)..."
  sudo npm install -g n
fi

if ! command -v pm2 &>/dev/null; then
  echo "📥 Installing pm2..."
  sudo npm install -g pm2
fi

# Upgrade to latest Node if using n
if command -v n &>/dev/null; then
  echo "⬆️ Ensuring latest Node.js..."
  sudo n latest
fi

echo "✅ All dependencies are ready!"

### 2. Setup Vikey
echo "🔑 Setting up Vikey..."
cd "$HOME"
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
DEFAULT_MODEL=llama-3.3-70b-instruct
VIKEY_API_KEY=${VIKEY_API_KEY}
EOF

# Start Vikey
nohup ./vikey-inference-linux > vikey.log 2>&1 &
sleep 3
echo "🚀 Vikey started! (logs: ~/vikey-inference/vikey.log)"

### 3. Test Vikey
echo "🔍 Testing Vikey with API..."
TEST_RESPONSE=$(curl -s -X POST https://api.vikey.ai/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${VIKEY_API_KEY}" \
  -d '{
    "model": "llama-3.3-70b-instruct",
    "max_tokens": 10,
    "n": 1,
    "stream": false,
    "messages": [{"role":"user","content":"hi"}]
  }')

if echo "$TEST_RESPONSE" | jq -e '.object=="chat.completion"' >/dev/null 2>&1; then
  echo "✅ Vikey API test successful!"
else
  echo "❌ Vikey API test failed!"
  echo "Response was: $TEST_RESPONSE"
fi

### 4. Crypto Wallet Generator
echo "💰 Setting up crypto wallet generator..."
cd "$HOME"
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

### 5. Wallet Handling
cd "$HOME/dria-nodes"
mkdir -p "$HOME/dria-nodes"

echo "💰 Wallet setup options:"
echo "1) Generate new wallet(s)"
echo "2) Use existing wallet.json"
read -p "Choose option [1/2]: " WALLET_OPTION

if [ "$WALLET_OPTION" == "1" ]; then
  read -p "🤔 How many wallets do you want to generate? " WALLET_COUNT
  cd "$HOME/crypto-generator"
  node crypto-generator.js "$WALLET_COUNT"
  WALLET_FILE="$HOME/crypto-generator/wallets.json"
elif [ "$WALLET_OPTION" == "2" ]; then
  read -p "📂 Enter path to your wallet.json: " WALLET_FILE
  WALLET_FILE="${WALLET_FILE/#\~/$HOME}" # expand ~
  if [ ! -f "$WALLET_FILE" ]; then
    echo "❌ File not found: $WALLET_FILE"
    exit 1
  fi
  if ! jq empty "$WALLET_FILE" 2>/dev/null; then
    echo "❌ Invalid JSON file format: $WALLET_FILE"
    exit 1
  fi
else
  echo "❌ Invalid option."
  exit 1
fi

### 6. Nodes per wallet
read -p "⚡ How many nodes should run per wallet? " NODES_PER_WALLET
if ! [[ "$NODES_PER_WALLET" =~ ^[0-9]+$ ]] || [ "$NODES_PER_WALLET" -lt 1 ]; then
  echo "❌ Invalid number."
  exit 1
fi

### 7. Generate docker-compose per wallet
WALLETS=$(cat "$WALLET_FILE" | jq -c '.[]')
i=1
for row in $WALLETS; do
  ADDR=$(echo "$row" | jq -r '.address')
  PRIV=$(echo "$row" | jq -r '.private_key')
  NODE_DIR="dria-node-$ADDR"
  mkdir -p "$NODE_DIR"

  echo "services:" > "$NODE_DIR/docker-compose.yml"
  for n in $(seq 1 $NODES_PER_WALLET); do
    cat >> "$NODE_DIR/docker-compose.yml" <<EOF
  compute_node_${i}_${n}:
    image: "firstbatch/dkn-compute-node:latest"
    environment:
      RUST_LOG: \${RUST_LOG:-none,dkn_compute=info}
      DKN_WALLET_SECRET_KEY: $PRIV
      DKN_MODELS: llama3.3:70b-instruct-q4_K_M,llama3.1:8b-instruct-q4_K_M,llama3.2:1b-instruct-q4_K_M
      DKN_P2P_LISTEN_ADDR: /ip4/0.0.0.0/tcp/$((4000+n))
      OLLAMA_HOST: http://10.172.1.1
      OLLAMA_PORT: 14441
      OLLAMA_AUTO_PULL: true
    networks:
      dria-nodes:
    restart: "on-failure"

EOF
  done

  cat >> "$NODE_DIR/docker-compose.yml" <<EOF
networks:
  dria-nodes:
    external: true
EOF

  echo "📝 Wallet $ADDR → $NODES_PER_WALLET node(s) configured at $NODE_DIR"
  i=$((i+1))
done

### 8. Start & Restart helper
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
