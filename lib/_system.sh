#!/bin/bash
# 
# system management

#######################################
# creates user
# Arguments:
#   None
#######################################
system_create_user() {
  print_banner
  printf "${WHITE} 💻 Agora, vamos criar o usuário para a instancia...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - root <<'EOF'
  set -e
  if id -u deploy >/dev/null 2>&1; then
    usermod -aG sudo deploy || true
  else
    useradd -m -s /bin/bash -G sudo deploy
    echo "deploy:${mysql_root_password}" | chpasswd
  fi
EOF

  sleep 2
}

#######################################
# clones repostories using git
# Arguments:
#   None
#######################################
system_git_clone() {
  print_banner
  printf "${WHITE} 💻 Fazendo download do código Whaticket...${GRAY_LIGHT}"
  printf "\n\n"


  sleep 2

  sudo su - deploy <<EOF
  set -e
  mkdir -p "/home/deploy/${instancia_add}"
  git clone "${link_git}" "/home/deploy/${instancia_add}/"
EOF

  sleep 2
}

#######################################
# checks Ubuntu version and prints a friendly warning if unsupported
# Arguments:
#   None
#######################################
system_check_ubuntu() {
  print_banner
  printf "${WHITE} 💻 Verificando versão do Ubuntu...${GRAY_LIGHT}"
  printf "\n\n"
  sudo su - root <<'EOF'
  set -e
  . /etc/os-release
  case "$VERSION_ID" in
    22.04|24.04)
      echo "Ubuntu $VERSION_ID detectado. Suporte confirmado." ;;
    *)
      echo "Aviso: versão detectada ($VERSION_ID) não é 22.04 ou 24.04. A instalação pode funcionar, mas não é oficialmente suportada." ;;
  esac
EOF
  sleep 2
}

#######################################
# updates system
# Arguments:
#   None
#######################################
system_update() {
  print_banner
  printf "${WHITE} 💻 Vamos atualizar o sistema Whaticket...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - root <<'EOF'
  set -e
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
  # Remove Apache2 se instalado (conflita com Nginx)
  apt-get remove -y apache2 apache2-utils || true
  apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg lsb-release apt-transport-https \
    software-properties-common unzip build-essential locales
  locale-gen en_US.UTF-8 pt_BR.UTF-8 || true
EOF

  sleep 2
}



#######################################
# delete system
# Arguments:
#   None
#######################################
deletar_tudo() {
  print_banner
  printf "${WHITE} 💻 Vamos deletar o Whaticket...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - root <<EOF
  docker container rm redis-${empresa_delete} --force 2>/dev/null || true
  cd && rm -rf /etc/nginx/sites-enabled/${empresa_delete}-frontend
  cd && rm -rf /etc/nginx/sites-enabled/${empresa_delete}-backend
  cd && rm -rf /etc/nginx/sites-available/${empresa_delete}-frontend
  cd && rm -rf /etc/nginx/sites-available/${empresa_delete}-backend

  sleep 2

  # Drop PostgreSQL user and database (executar diretamente, não aninhado)
  sudo -u postgres dropuser ${empresa_delete} 2>/dev/null || true
  sudo -u postgres dropdb ${empresa_delete} 2>/dev/null || true
EOF

sleep 2

sudo su - deploy <<EOF
 rm -rf /home/deploy/${empresa_delete}
 pm2 delete ${empresa_delete}-frontend ${empresa_delete}-backend
 pm2 save
EOF

  sleep 2

  print_banner
  printf "${WHITE} 💻 Remoção da Instancia/Empresa ${empresa_delete} realizado com sucesso ...${GRAY_LIGHT}"
  printf "\n\n"


  sleep 2

}

#######################################
# bloquear system
# Arguments:
#   None
#######################################
configurar_bloqueio() {
  print_banner
  printf "${WHITE} 💻 Vamos bloquear o Whaticket...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

sudo su - deploy <<EOF
 pm2 stop ${empresa_bloquear}-backend
 pm2 save
EOF

  sleep 2

  print_banner
  printf "${WHITE} 💻 Bloqueio da Instancia/Empresa ${empresa_bloquear} realizado com sucesso ...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2
}


#######################################
# desbloquear system
# Arguments:
#   None
#######################################
configurar_desbloqueio() {
  print_banner
  printf "${WHITE} 💻 Vamos Desbloquear o Whaticket...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

sudo su - deploy <<EOF
 pm2 start ${empresa_bloquear}-backend
 pm2 save
EOF

  sleep 2

  print_banner
  printf "${WHITE} 💻 Desbloqueio da Instancia/Empresa ${empresa_desbloquear} realizado com sucesso ...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2
}

#######################################
# alter dominio system
# Arguments:
#   None
#######################################
configurar_dominio() {
  print_banner
  printf "${WHITE} 💻 Vamos Alterar os Dominios do Whaticket...${GRAY_LIGHT}"
  printf "\n\n"

sleep 2

  sudo su - root <<EOF
  cd && rm -rf /etc/nginx/sites-enabled/${empresa_dominio}-frontend
  cd && rm -rf /etc/nginx/sites-enabled/${empresa_dominio}-backend  
  cd && rm -rf /etc/nginx/sites-available/${empresa_dominio}-frontend
  cd && rm -rf /etc/nginx/sites-available/${empresa_dominio}-backend
EOF

sleep 2

  sudo su - deploy <<EOF
  cd && cd /home/deploy/${empresa_dominio}/frontend
  sed -i "1c\REACT_APP_BACKEND_URL=https://${alter_backend_url}" .env
  cd && cd /home/deploy/${empresa_dominio}/backend
  sed -i "2c\BACKEND_URL=https://${alter_backend_url}" .env
  sed -i "3c\FRONTEND_URL=https://${alter_frontend_url}" .env 
EOF

sleep 2
   
   backend_hostname=$(echo "${alter_backend_url/https:\/\/}")

 sudo su - root <<EOF
  cat > /etc/nginx/sites-available/${empresa_dominio}-backend << 'END'
server {
  server_name $backend_hostname;
  location / {
    proxy_pass http://127.0.0.1:$alter_backend_port;
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
ln -sf /etc/nginx/sites-available/${empresa_dominio}-backend /etc/nginx/sites-enabled
EOF

sleep 2

frontend_hostname=$(echo "${alter_frontend_url/https:\/\/}")

sudo su - root << EOF
cat > /etc/nginx/sites-available/${empresa_dominio}-frontend << 'END'
server {
  server_name $frontend_hostname;
  location / {
    proxy_pass http://127.0.0.1:$alter_frontend_port;
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
ln -sf /etc/nginx/sites-available/${empresa_dominio}-frontend /etc/nginx/sites-enabled
EOF

 sleep 2

 sudo su - root <<'EOF'
  set -e
  if nginx -t; then
    systemctl reload nginx
  else
    echo "nginx -t falhou. Mantendo configuração atual." >&2
    systemctl status nginx -l || true
    exit 1
  fi
EOF

  sleep 2

  backend_domain=$(echo "${backend_url/https:\/\/}")
  frontend_domain=$(echo "${frontend_url/https:\/\/}")

  sudo su - root <<EOF
  certbot -m "$deploy_email" \
          --nginx \
          --agree-tos \
          --non-interactive \
          --domains "$backend_domain,$frontend_domain" || true
EOF

  sleep 2

  print_banner
  printf "${WHITE} 💻 Alteração de dominio da Instancia/Empresa ${empresa_dominio} realizado com sucesso ...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2
}

#######################################
# installs node
# Arguments:
#   None
#######################################
system_node_install() {
  print_banner
  printf "${WHITE} 💻 Instalando nodejs...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - root <<'EOF'
  set -e
  # Método alternativo para Node.js 20 LTS (compatível com Ubuntu 22.04/24.04)
  if [ ! -f /etc/apt/keyrings/nodesource.gpg ]; then
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" > /etc/apt/sources.list.d/nodesource.list
    apt-get update -y
  fi
  apt-get install -y nodejs
  npm install -g npm@latest
  # Use PostgreSQL from Ubuntu repo (compatible with 22.04/24.04)
  apt-get update -y && apt-get install -y postgresql
  timedatectl set-timezone America/Sao_Paulo
EOF

  sleep 2
}
#######################################
# installs docker
# Arguments:
#   None
#######################################
system_docker_install() {
  print_banner
  printf "${WHITE} 💻 Instalando docker...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - root <<'EOF'
  set -e
  apt-get install -y ca-certificates curl gnupg apt-transport-https
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  . /etc/os-release
  echo \
    "deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \${VERSION_CODENAME} stable" | \
    tee /etc/apt/sources.list.d/docker.list > /dev/null
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
EOF

  sleep 2
}

#######################################
# Ask for file location containing
# multiple URL for streaming.
# Globals:
#   WHITE
#   GRAY_LIGHT
#   BATCH_DIR
#   PROJECT_ROOT
# Arguments:
#   None
#######################################
system_puppeteer_dependencies() {
  print_banner
  printf "${WHITE} 💻 Instalando puppeteer dependencies...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - root <<'EOF'
  set -e
  apt-get install -y --no-install-recommends \
    libxshmfence-dev libgbm-dev wget unzip fontconfig locales \
    libasound2 libatk1.0-0 libatk-bridge2.0-0 libc6 libcairo2 libcups2 libdbus-1-3 \
    libexpat1 libfontconfig1 libgcc-s1 libgdk-pixbuf-2.0-0 libglib2.0-0 \
    libgtk-3-0 libnspr4 libpango-1.0-0 libpangocairo-1.0-0 libstdc++6 \
    libx11-6 libx11-xcb1 libxcb1 libxcomposite1 libxcursor1 libxdamage1 \
    libxext6 libxfixes3 libxi6 libxrandr2 libxrender1 libxss1 libxtst6 \
    ca-certificates fonts-liberation libayatana-appindicator3-1 libnss3 \
    lsb-release xdg-utils libdrm2 libxkbcommon0 libatspi2.0-0
  locale-gen en_US.UTF-8 pt_BR.UTF-8 || true
EOF

  sleep 2
}

#######################################
# creates swap if system has low memory
# Arguments:
#   None
#######################################
system_create_swap() {
  print_banner
  printf "${WHITE} 💻 Verificando/criando swap para sistemas com pouca memória...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - root <<'EOF'
  set -e
  # Verifica se já existe swap
  if [ -f /swapfile ]; then
    echo "Swap já existe em /swapfile"
    exit 0
  fi

  # Verifica memória total
  total_mem=$(free -m | awk '/^Mem:/{print $2}')
  if [ "$total_mem" -lt 2048 ]; then
    echo "Sistema com pouca memória (${total_mem}MB). Criando swap de 2GB..."
    fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    echo "Swap criado com sucesso!"
  else
    echo "Sistema tem memória suficiente (${total_mem}MB). Swap não necessário."
  fi
EOF

  sleep 2
}

#######################################
# installs pm2
# Arguments:
#   None
#######################################
system_pm2_install() {
  print_banner
  printf "${WHITE} 💻 Instalando pm2...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - root <<EOF
  npm install -g pm2

EOF

  sleep 2
}

#######################################
# installs snapd
# Arguments:
#   None
#######################################
system_snapd_install() {
  print_banner
  printf "${WHITE} 💻 Instalando snapd...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - root <<EOF
  apt install -y snapd
  snap install core
  snap refresh core
EOF

  sleep 2
}

#######################################
# installs certbot
# Arguments:
#   None
#######################################
system_certbot_install() {
  print_banner
  printf "${WHITE} 💻 Instalando certbot...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - root <<EOF
  apt-get remove certbot
  snap install --classic certbot
  ln -s /snap/bin/certbot /usr/bin/certbot
EOF

  sleep 2
}

#######################################
# installs nginx
# Arguments:
#   None
#######################################
system_nginx_install() {
  print_banner
  printf "${WHITE} 💻 Instalando nginx...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - root <<'EOF'
  set -e
  apt-get install -y nginx
  rm -f /etc/nginx/sites-enabled/default || true
EOF

  sleep 2
}

#######################################
# restarts nginx
# Arguments:
#   None
#######################################
system_nginx_restart() {
  print_banner
  printf "${WHITE} 💻 recarregando nginx com validação...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - root <<'EOF'
  set -e
  if nginx -t; then
    systemctl reload nginx
  else
    echo "nginx -t falhou. Mantendo configuração atual." >&2
    systemctl status nginx -l || true
    exit 1
  fi
  systemctl enable nginx || true
EOF

  sleep 2
}

#######################################
# setup for nginx.conf
# Arguments:
#   None
#######################################
system_nginx_conf() {
  print_banner
  printf "${WHITE} 💻 configurando nginx...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

sudo su - root << EOF

cat > /etc/nginx/conf.d/deploy.conf << 'END'
client_max_body_size 100M;
END

EOF

  sleep 2
}

#######################################
# installs nginx
# Arguments:
#   None
#######################################
system_certbot_setup() {
  print_banner
  printf "${WHITE} 💻 Configurando certbot...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  backend_domain=$(echo "${backend_url/https:\/\/}")
  frontend_domain=$(echo "${frontend_url/https:\/\/}")

  sudo su - root <<EOF
  set -e
  certbot -m "$deploy_email" \
          --nginx \
          --agree-tos \
          --non-interactive \
          --domains "$backend_domain","$frontend_domain" || true
EOF

  sleep 2
}

#######################################
# configure firewall (ufw) if present/enabled
# Arguments:
#   None
#######################################
system_firewall_setup() {
  print_banner
  printf "${WHITE} 🔒 Ajustando firewall (se aplicável)...${GRAY_LIGHT}"
  printf "\n\n"
  sleep 2

  sudo su - root <<'EOF'
  set -e
  if command -v ufw >/dev/null 2>&1; then
    if ufw status | grep -q "Status: active"; then
      ufw allow 80/tcp || true
      ufw allow 443/tcp || true
    fi
  fi
EOF
  sleep 2
}

#######################################
# post-install healthcheck
# Arguments:
#   None
#######################################
system_post_install_healthcheck() {
  print_banner
  printf "${WHITE} 🩺 Verificando serviços pós-instalação...${GRAY_LIGHT}"
  printf "\n\n"
  sleep 1

  sudo su - root <<'EOF'
  set -e
  echo "[NGINX]"; systemctl --no-pager -l status nginx || true
  echo "\n[Docker]"; docker ps --format 'table {{.Names}}\t{{.Status}}' || true
  echo "\n[PM2] (usuário deploy)"; sudo -u deploy pm2 list || true
  echo "\n[PostgreSQL]"; sudo -u postgres psql -tAc 'SELECT version()' || true
  echo "\n[Certbot]"; certbot --version || true
EOF
  sleep 1
}
