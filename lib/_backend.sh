#!/bin/bash
#
# functions for setting up app backend
#######################################
# creates REDIS db using docker
# Arguments:
#   None
#######################################
backend_redis_create() {
  print_banner
  printf "${WHITE} 💻 Criando Redis & Banco Postgres...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - root <<EOF
  set -e
  # Adiciona usuário deploy ao grupo docker
  usermod -aG docker deploy || true
  # Cria diretório para dados do Redis com permissões corretas
  mkdir -p "/home/deploy/${instancia_add}/redis"
  chown -R deploy:deploy "/home/deploy/${instancia_add}/redis"

  # Inicia Docker se não estiver rodando
  systemctl start docker || true
  systemctl enable docker || true

  # Cria container Redis (executando como root para evitar problemas de permissão)
  if ! docker ps -a --format '{{.Names}}' | grep -q "^redis-${instancia_add}$"; then
    docker run --name "redis-${instancia_add}" -p "${redis_port}:6379" --restart always \
      -v "/home/deploy/${instancia_add}/redis:/data" --detach redis:7.2-alpine \
      redis-server --appendonly yes --requirepass "${mysql_root_password}"
  else
    docker start "redis-${instancia_add}" || true
  fi

  # Create Postgres DB and user idempotently
  sudo -u postgres bash -lc "psql -tAc \"SELECT 1 FROM pg_roles WHERE rolname='${instancia_add}'\" | grep -q 1 || createuser -s ${instancia_add}"
  sudo -u postgres bash -lc "psql -tAc \"SELECT 1 FROM pg_database WHERE datname='${instancia_add}'\" | grep -q 1 || createdb ${instancia_add}"
  sudo -u postgres psql -v ON_ERROR_STOP=1 -c "ALTER USER \"${instancia_add}\" WITH PASSWORD '${mysql_root_password}'" || true
EOF

sleep 2

}

#######################################
# sets environment variable for backend.
# Arguments:
#   None
#######################################
backend_set_env() {
  print_banner
  printf "${WHITE} 💻 Configurando variáveis de ambiente (backend)...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  # ensure idempotency
  backend_url=$(echo "${backend_url/https:\/\/}")
  backend_url=${backend_url%%/*}
  backend_url=https://$backend_url

  # ensure idempotency
  frontend_url=$(echo "${frontend_url/https:\/\/}")
  frontend_url=${frontend_url%%/*}
  frontend_url=https://$frontend_url

sudo su - deploy << EOF
  cat <<[-]EOF > /home/deploy/${instancia_add}/backend/.env
NODE_ENV=
BACKEND_URL=${backend_url}
FRONTEND_URL=${frontend_url}
PROXY_PORT=443
PORT=${backend_port}

DB_DIALECT=postgres
DB_HOST=localhost
DB_PORT=5432
DB_USER=${instancia_add}
DB_PASS=${mysql_root_password}
DB_NAME=${instancia_add}

JWT_SECRET=${jwt_secret}
JWT_REFRESH_SECRET=${jwt_refresh_secret}

REDIS_URI=redis://:${mysql_root_password}@127.0.0.1:${redis_port}
REDIS_OPT_LIMITER_MAX=1
REDIS_OPT_LIMITER_DURATION=3000

USER_LIMIT=${max_user}
CONNECTIONS_LIMIT=${max_whats}
CLOSED_SEND_BY_ME=true

MAIL_HOST="smtp.hostinger.com"
MAIL_USER="contato@seusite.com"
MAIL_PASS="senha"
MAIL_FROM="Recuperar Senha <contato@seusite.com>"
MAIL_PORT="465"

[-]EOF
EOF

  sleep 2
}

#######################################
# installs node.js dependencies
# Arguments:
#   None
#######################################
backend_node_dependencies() {
  print_banner
  printf "${WHITE} 💻 Instalando dependências do backend...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - deploy <<EOF
  cd /home/deploy/${instancia_add}/backend
  npm install
EOF

  sleep 2
}

#######################################
# compiles backend code
# Arguments:
#   None
#######################################
backend_node_build() {
  print_banner
  printf "${WHITE} 💻 Compilando o código do backend...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - deploy <<EOF
  cd /home/deploy/${instancia_add}/backend
  # Aumenta memória para evitar erros de heap durante o build
  export NODE_OPTIONS="--max-old-space-size=4096"
  npm run build
EOF

  sleep 2
}

#######################################
# updates frontend code
# Arguments:
#   None
#######################################
backend_update() {
  print_banner
  printf "${WHITE} 💻 Atualizando o backend...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - deploy <<EOF
  cd /home/deploy/${empresa_atualizar}
  pm2 stop ${empresa_atualizar}-backend
  git pull
  cd /home/deploy/${empresa_atualizar}/backend
  npm install
  npm update -f
  npm install @types/fs-extra
  rm -rf dist
  # Aumenta memória para evitar erros de heap durante o build
  export NODE_OPTIONS="--max-old-space-size=4096"
  npm run build
  npx sequelize db:migrate
  npx sequelize db:migrate
  npx sequelize db:seed
  pm2 start ${empresa_atualizar}-backend
  pm2 save
EOF

  sleep 2
}

#######################################
# runs db migrate
# Arguments:
#   None
#######################################
backend_db_migrate() {
  print_banner
  printf "${WHITE} 💻 Executando db:migrate...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - deploy <<EOF
  cd /home/deploy/${instancia_add}/backend
  npx sequelize db:migrate
EOF

  sleep 2
}

#######################################
# runs db seed
# Arguments:
#   None
#######################################
backend_db_seed() {
  print_banner
  printf "${WHITE} 💻 Executando db:seed...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - deploy <<EOF
  cd /home/deploy/${instancia_add}/backend
  npx sequelize db:seed:all
EOF

  sleep 2
}

#######################################
# starts backend using pm2 in 
# production mode.
# Arguments:
#   None
#######################################
backend_start_pm2() {
  print_banner
  printf "${WHITE} 💻 Iniciando pm2 (backend)...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - deploy <<EOF
  cd /home/deploy/${instancia_add}/backend
  pm2 start dist/server.js --name ${instancia_add}-backend
EOF

  sleep 2
}

#######################################
# safely upgrade or recreate Redis container to pinned version with persistence
# Arguments:
#   None
#######################################
backend_redis_upgrade_safe() {
 print_banner
 printf "${WHITE} 💻 Atualizando Redis (seguro, com persistência)...${GRAY_LIGHT}"
 printf "\n\n"
 sleep 2

 sudo su - root <<EOF
 set -e
 cname="redis-${instancia_add}"
 data_dir="/home/deploy/${instancia_add}/redis"
 mkdir -p "$data_dir"
 chown -R deploy:deploy "$data_dir"

 # Inicia Docker se não estiver rodando
 systemctl start docker || true

 if docker ps -a --format '{{.Names}}' | grep -q "^$cname$"; then
   echo "Parando contêiner existente $cname..."
   docker stop "$cname" || true
   echo "Removendo contêiner existente $cname..."
   docker rm "$cname" || true
 fi

 echo "Subindo Redis 7.2 com persistência..."
 docker run --name "$cname" -p "${redis_port}:6379" --restart always \
   -v "$data_dir:/data" --detach redis:7.2-alpine \
   redis-server --appendonly yes --requirepass "${mysql_root_password}"
EOF

 sleep 2
}

#######################################
# updates frontend code
# Arguments:
#   None
#######################################
backend_nginx_setup() {
  print_banner
  printf "${WHITE} 💻 Configurando nginx (backend)...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  backend_hostname=$(echo "${backend_url/https:\/\/}")

sudo su - root << EOF
cat > /etc/nginx/sites-available/${instancia_add}-backend << 'END'
server {
  server_name $backend_hostname;
  location / {
    proxy_pass http://127.0.0.1:$backend_port;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection 'upgrade';
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_cache_bypass \$http_upgrade;
  }
}
END
ln -sf /etc/nginx/sites-available/${instancia_add}-backend /etc/nginx/sites-enabled
EOF

  sleep 2
}
