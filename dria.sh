#!/bin/bash

# ========== Config ==========
REPO_URL="https://github.com/firstbatchxyz/dkn-compute-node"
PRIVATE_KEY_FILE="$HOME/.dria_node.env"
DOCKER_NETWORK="dria-network"
DOCKER_SUBNET="10.173.1.0/24"
# ============================

# Cek argumen
if [[ "$1" != "setup" || "$2" != "--count" || -z "$3" ]]; then
  echo "❌ Usage: ./dria-setup.sh setup --count <jumlah_node>"
  exit 1
fi

COUNT=$3

# 🚀 Cek dan install docker
install_docker_if_needed() {
  if ! command -v docker &>/dev/null; then
    echo "🔧 Installing Docker..."
    curl -fsSL https://get.docker.com | bash
    sudo usermod -aG docker $USER
  else
    echo "✅ Docker sudah terinstall."
  fi
}

# 🔍 Deteksi docker compose
detect_compose() {
  if command -v docker-compose &>/dev/null; then
    COMPOSE_BIN="docker-compose"
  elif docker compose version &>/dev/null; then
    COMPOSE_BIN="docker compose"
  else
    echo "❌ Docker Compose tidak ditemukan."
    exit 1
  fi
  echo "✅ Menggunakan: $COMPOSE_BIN"
}

# 🔐 Ambil PRIVATE_KEY
get_private_key() {
  if [ -f "$PRIVATE_KEY_FILE" ]; then
    source "$PRIVATE_KEY_FILE"
    if [ -n "$PRIVATE_KEY" ]; then
      echo "✅ PRIVATE_KEY ditemukan di $PRIVATE_KEY_FILE"
      return
    fi
  fi

  echo "🔐 Input PRIVATE_KEY kamu (32-byte hex):"
  read -rp "PRIVATE_KEY: " PRIVATE_KEY
  echo "PRIVATE_KEY=$PRIVATE_KEY" >"$PRIVATE_KEY_FILE"
  echo "✅ Disimpan di $PRIVATE_KEY_FILE"
}

# 🌐 Setup docker network
setup_docker_network() {
  if ! docker network ls | grep -q "$DOCKER_NETWORK"; then
    echo "🌐 Membuat docker network: $DOCKER_NETWORK"
    docker network create --subnet=$DOCKER_SUBNET $DOCKER_NETWORK
  else
    echo "✅ Docker network $DOCKER_NETWORK sudah ada."
  fi
}

# 🧱 Setup node
setup_node() {
  local i=$1
  local DIR="dkn-compute-node-$i"
  local PORT=$((11433 + i))

  echo "🔧 Setup node $i di folder $DIR (PORT: $PORT)..."

  if [ ! -d "$DIR" ]; then
    git clone "$REPO_URL" "$DIR"
  else
    echo "📂 Folder $DIR sudah ada, skip cloning."
  fi

  cd "$DIR" || exit

  # nginx.conf
  cat >nginx.conf <<EOF
events {}

http {
    server {
        listen $PORT;

        location / {
            proxy_pass http://10.173.1.1:14444;
            proxy_http_version 1.1;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        }
    }
}
EOF

  # compose.yml
  cat >compose.yml <<EOF
services:
  nginx:
    image: nginx:alpine
    networks:
      dria-network:
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
    restart: unless-stopped

  compute:
    image: "firstbatch/dkn-compute-node:latest"
    environment:
      RUST_LOG: \${RUST_LOG:-none,dkn_compute=info}
      DKN_WALLET_SECRET_KEY: \${DKN_WALLET_SECRET_KEY}
      DKN_MODELS: \${DKN_MODELS}
      DKN_P2P_LISTEN_ADDR: \${DKN_P2P_LISTEN_ADDR}
      DKN_RELAY_NODES: \${DKN_RELAY_NODES}
      DKN_BOOTSTRAP_NODES: \${DKN_BOOTSTRAP_NODES}
      OPENAI_API_KEY: \${OPENAI_API_KEY}
      GEMINI_API_KEY: \${GEMINI_API_KEY}
      OPENROUTER_API_KEY: \${OPENROUTER_API_KEY}
      SERPER_API_KEY: \${SERPER_API_KEY}
      JINA_API_KEY: \${JINA_API_KEY}
      OLLAMA_HOST: \${OLLAMA_HOST}
      OLLAMA_PORT: \${OLLAMA_PORT}
      OLLAMA_AUTO_PULL: \${OLLAMA_AUTO_PULL:-true}
    restart: "on-failure"
    depends_on:
      - nginx
    networks:
      dria-network:

volumes:
  ollama:
networks:
  dria-network:
    external: true
EOF

  # .env
  cat >.env <<EOF
## DRIA ##
DKN_WALLET_SECRET_KEY=$PRIVATE_KEY
DKN_MODELS=deepseek-r1:1.5b,deepseek-r1:7b,deepseek-r1:8b,deepseek-r1:14b,qwen2.5:7b-instruct-fp16,hellord/mxbai-embed-large-v1:f16
DKN_P2P_LISTEN_ADDR=/ip4/0.0.0.0/tcp/4001
DKN_RELAY_NODES=
DKN_BOOTSTRAP_NODES=
DKN_BATCH_SIZE=

## Ollama ##
OLLAMA_HOST=http://nginx
OLLAMA_PORT=$PORT
OLLAMA_AUTO_PULL=false

## API Keys ##
OPENAI_API_KEY=
GEMINI_API_KEY=
OPENROUTER_API_KEY=
SERPER_API_KEY=
JINA_API_KEY=

## Log ##
RUST_LOG=none
EOF

  # Jalankan
  $COMPOSE_BIN up -d

  cd ..
}

# === MAIN ===
install_docker_if_needed
detect_compose
get_private_key
setup_docker_network

for i in $(seq 1 "$COUNT"); do
  setup_node "$i"
done

echo "🎉 Selesai setup $COUNT node!"
