# 🧩 Dria Nodes Setup Script

**File:** `dria.sh`
**Repo:** [ai-nodes-setup](https://github.com/direkturcrypto/ai-nodes-setup)
**Credits:** powered by **direkturcrypto** 🙏

This script automates the installation and setup of:

* Docker & Docker Compose 🐳
* Node.js, npm, pm2 📦
* Vikey Inference 🔑
* EVM crypto wallets 💰
* Dria nodes ⚡ (1 node per wallet generated)

---

## 🔧 Prerequisites

* Ubuntu/Debian-based Linux machine
* `sudo` access
* Internet connection

---

## 📥 Installation

Clone the repository:

```bash
git clone https://github.com/direkturcrypto/ai-nodes-setup
cd ai-nodes-setup
```

Make the script executable:

```bash
chmod +x dria.sh
```

---

## 🚀 Usage

Run the setup script:

```bash
./dria.sh
```

### During setup you will be asked:

1. **Enter your `VIKEY_API_KEY`** 🔐
   This key will be saved in the Vikey `.env` file.

2. **How many wallets to generate** 💰
   Example: if you enter `5`, it will generate **5 wallets** and create **5 Dria nodes**.

---

## 📂 What Gets Created

* `~/vikey-inference/` → Vikey inference server + `.env`
* `~/crypto-generator/wallets.json` → Generated wallets (address & private key)
* `~/dria-nodes/dria-node-<wallet_address>/docker-compose.yml` → Node configs
* `~/manage-dria.sh` → Helper script to manage Dria nodes

---

## ⚡ Managing Dria Nodes

After setup, use the helper script:

### Start all nodes

```bash
./manage-dria.sh start
```

✅ Brings up all Dria nodes in the background.

### Restart all nodes

```bash
./manage-dria.sh restart
```

♻️ Restarts all running nodes.

---

## 🔍 Verify Vikey

Run:

```bash
curl http://localhost:14441
```

Expected response:

```json
{"error":"Endpoint not supported"}
```

This confirms Vikey is running correctly.

---

## 🪵 Logs

To check Vikey logs:

```bash
tail -f ~/vikey-inference/vikey.log
```

To check Dria node logs:

```bash
cd ~/dria-nodes/dria-node-<WALLET_ADDRESS>
docker-compose logs -f
```

---

## 🙏 Credits

This setup is proudly **powered by direkturcrypto**.

Would you like me to also add a **status command** in `manage-dria.sh` (so users can see ✅ UP / ❌ DOWN for each node without digging into Docker logs)?
