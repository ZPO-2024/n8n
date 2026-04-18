#!/bin/bash
# start.sh - Configure .env and launch n8n stack (IP-based, no domain required)
# If .env already exists, reuse existing credentials to avoid encryption key mismatch
set -e

N8N_DIR=/opt/n8n
SERVER_IP=178.104.132.122

# Only generate new credentials if .env doesn't exist
if [ ! -f "$N8N_DIR/.env" ]; then
  echo "Generating new credentials..."
  DB_PASS=$(openssl rand -hex 24)
  N8N_ENC_KEY=$(openssl rand -hex 32)
  N8N_PASS=$(openssl rand -hex 12)

  # Write .env
  cat > $N8N_DIR/.env << EOF
# Server
SERVER_IP=${SERVER_IP}
DOMAIN=${SERVER_IP}

# Postgres
POSTGRES_DB=n8n
POSTGRES_USER=n8n
POSTGRES_PASSWORD=${DB_PASS}

# n8n
N8N_ENCRYPTION_KEY=${N8N_ENC_KEY}
N8N_USER_MANAGEMENT_JWT_SECRET=$(openssl rand -hex 32)
N8N_DEFAULT_USER_EMAIL=admin@roguewave.local
N8N_DEFAULT_USER_PASSWORD=${N8N_PASS}

# Webhook
WEBHOOK_URL=http://${SERVER_IP}:5678
N8N_EDITOR_BASE_URL=http://${SERVER_IP}:5678
EOF
  echo "Credentials generated and saved to .env"
  echo "n8n Password: ${N8N_PASS}"
else
  echo "Reusing existing .env credentials"
  source $N8N_DIR/.env
fi

# Write docker-compose override for IP-only (no Caddy TLS needed yet)
cat > $N8N_DIR/docker-compose.yml << 'COMPOSE'
version: '3.8'
services:
  postgres:
    image: postgres:16-alpine
    restart: unless-stopped
    env_file: .env
    environment:
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER}"]
      interval: 10s
      timeout: 5s
      retries: 5
  n8n:
    image: n8nio/n8n:latest
    restart: unless-stopped
    ports:
      - "5678:5678"
    env_file: .env
    environment:
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=${POSTGRES_DB}
      - DB_POSTGRESDB_USER=${POSTGRES_USER}
      - DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD}
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
      - N8N_HOST=${SERVER_IP}
      - N8N_PORT=5678
      - N8N_PROTOCOL=http
      - WEBHOOK_URL=${WEBHOOK_URL}
      - N8N_EDITOR_BASE_URL=${N8N_EDITOR_BASE_URL}
      - GENERIC_TIMEZONE=America/New_York
      - N8N_LOG_LEVEL=info
      - N8N_SECURE_COOKIE=false
    volumes:
      - n8n_data:/home/node/.n8n
    depends_on:
      postgres:
        condition: service_healthy
volumes:
  postgres_data:
  n8n_data:
COMPOSE

# Open firewall port 5678
ufw allow 5678/tcp || true

# Start stack
cd $N8N_DIR
docker compose pull
docker compose up -d

# Wait for n8n to be ready
echo "Waiting for n8n to start..."
sleep 15
docker compose ps
echo ""
echo "========================================"
echo "n8n is live!"
echo "URL: http://${SERVER_IP}:5678"
echo "Email: admin@roguewave.local"
echo "========================================"
echo ""
echo "SAVE THESE CREDENTIALS - check .env file for password"
