#!/bin/bash
# rogue-wolf-n8n-prod — Full Stack Bootstrap
# Run as root: bash <(curl -fsSL https://raw.githubusercontent.com/ZPO-2024/n8n/master/deploy/setup.sh)
set -euo pipefail

echo "=== [1/7] System update ==="
apt-get update -qq && apt-get upgrade -y -qq
apt-get install -y -qq curl git nano ufw fail2ban

echo "=== [2/7] Install Docker ==="
curl -fsSL https://get.docker.com | sh
systemctl enable --now docker
apt-get install -y -qq docker-compose-plugin

echo "=== [3/7] Directory structure ==="
mkdir -p /opt/n8n/{data,postgres,redis}
mkdir -p /opt/n8n/caddy/{data,config}
chmod 700 /opt/n8n

echo "=== [4/7] Write docker-compose.yml ==="
cat > /opt/n8n/docker-compose.yml << 'COMPOSE'
version: '3.8'

volumes:
  n8n_data:
    driver: local
    driver_opts: {type: none, o: bind, device: /opt/n8n/data}
  postgres_data:
    driver: local
    driver_opts: {type: none, o: bind, device: /opt/n8n/postgres}
  redis_data:
    driver: local
    driver_opts: {type: none, o: bind, device: /opt/n8n/redis}

networks:
  n8n_net:
    driver: bridge

services:

  postgres:
    image: postgres:16-alpine
    restart: unless-stopped
    networks: [n8n_net]
    environment:
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    restart: unless-stopped
    networks: [n8n_net]
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  n8n:
    image: docker.n8n.io/n8nio/n8n:latest
    restart: unless-stopped
    networks: [n8n_net]
    ports:
      - "127.0.0.1:5678:5678"
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    env_file: .env
    environment:
      - N8N_PORT=5678
    volumes:
      - n8n_data:/home/node/.n8n
      - /opt/n8n/data/custom:/home/node/.n8n/custom

  n8n-worker:
    image: docker.n8n.io/n8nio/n8n:latest
    restart: unless-stopped
    networks: [n8n_net]
    command: worker
    depends_on:
      - n8n
    env_file: .env
    volumes:
      - n8n_data:/home/node/.n8n
      - /opt/n8n/data/custom:/home/node/.n8n/custom

  caddy:
    image: caddy:2-alpine
    restart: unless-stopped
    networks: [n8n_net]
    ports:
      - "80:80"
      - "443:443"
      - "443:443/udp"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - /opt/n8n/caddy/data:/data
      - /opt/n8n/caddy/config:/config
    depends_on:
      - n8n
COMPOSE

echo "=== [5/7] Write Caddyfile ==="
cat > /opt/n8n/Caddyfile << 'CADDY'
# Replace n8n.yourdomain.com with your actual domain
n8n.yourdomain.com {
    reverse_proxy n8n:5678 {
        flush_interval -1
    }
    encode gzip
    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains"
        X-Content-Type-Options "nosniff"
        X-Frame-Options "SAMEORIGIN"
        -Server
    }
}
CADDY

echo "=== [6/7] Write .env template ==="
ENCRYPTION_KEY=$(openssl rand -hex 32)
DB_PASS=$(openssl rand -base64 24 | tr -d '=+/' | cut -c1-24)
cat > /opt/n8n/.env << ENVFILE
# --- DOMAIN (update before starting) ---
N8N_HOST=n8n.yourdomain.com
N8N_PROTOCOL=https
WEBHOOK_URL=https://n8n.yourdomain.com/

# --- SECURITY (auto-generated) ---
N8N_ENCRYPTION_KEY=${ENCRYPTION_KEY}

# --- DATABASE ---
DB_TYPE=postgresdb
DB_POSTGRESDB_HOST=postgres
DB_POSTGRESDB_PORT=5432
DB_POSTGRESDB_DATABASE=n8n
DB_POSTGRESDB_USER=n8n
DB_POSTGRESDB_PASSWORD=${DB_PASS}
POSTGRES_DB=n8n
POSTGRES_USER=n8n
POSTGRES_PASSWORD=${DB_PASS}

# --- QUEUE MODE ---
EXECUTIONS_MODE=queue
QUEUE_BULL_REDIS_HOST=redis
QUEUE_BULL_REDIS_PORT=6379

# --- TIMEZONE ---
GENERIC_TIMEZONE=America/New_York
TZ=America/New_York

# --- UI AUTH (change password!) ---
N8N_BASIC_AUTH_ACTIVE=true
N8N_BASIC_AUTH_USER=admin
N8N_BASIC_AUTH_PASSWORD=ChangeMe_$(openssl rand -hex 6)

# --- CUSTOM NODES ---
N8N_CUSTOM_EXTENSIONS=/home/node/.n8n/custom
ENVILE

echo "=== [7/7] UFW firewall ==="
ufw --force enable
ufw allow 22/tcp comment 'SSH'
ufw allow 80/tcp comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'
ufw allow 443/udp comment 'HTTPS UDP (HTTP/3)'
ufw default deny incoming
ufw default allow outgoing

# Custom nodes directory
mkdir -p /opt/n8n/data/custom/nodes

echo ""
echo "============================================="
echo " SETUP COMPLETE — rogue-wolf-n8n-prod"
echo "============================================="
echo ""
echo " NEXT STEPS:"
echo " 1. Edit /opt/n8n/.env — update N8N_HOST + N8N_BASIC_AUTH_PASSWORD"
echo " 2. Edit /opt/n8n/Caddyfile — update domain"
echo " 3. Point DNS A record to 178.104.132.122"
echo " 4. Run: cd /opt/n8n && docker compose up -d"
echo " 5. Check: docker compose logs -f n8n"
echo ""
echo " DB password saved in /opt/n8n/.env"
cat /opt/n8n/.env | grep DB_POSTGRESDB_PASSWORD
echo ""
