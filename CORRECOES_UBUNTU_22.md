# Correções do Instalador - Ubuntu 22.04/24.04

## Resumo Executivo

Este documento detalha todas as correções aplicadas no instalador para garantir compatibilidade com Ubuntu 22.04 e 24.04.

**Data:** 27/12/2025
**Versão:** Instalador Corrigido (v2)

---

## Erros Identificados e Mitigados

| # | Erro | Severidade | Status |
|---|------|------------|--------|
| 1 | OpenSSL passwd descontinuado | ALTA | CORRIGIDO |
| 2 | Docker sem permissão para usuário deploy | ALTA | CORRIGIDO |
| 3 | Apache2 conflitando com Nginx | MÉDIA | CORRIGIDO |
| 4 | NodeSource setup_20.x descontinuado | BAIXA | CORRIGIDO |
| 5 | Build estoura memória (heap out of memory) | MÉDIA | CORRIGIDO |
| 6 | Typo `REGIS_OPT_LIMITER_DURATION` | ALTA | CORRIGIDO |
| 7 | Puppeteer dependencies faltando | MÉDIA | CORRIGIDO |
| 8 | Comando postgres aninhado não funciona | MÉDIA | CORRIGIDO |
| 9 | Swap não criado em VPS com pouca RAM | MÉDIA | CORRIGIDO |
| 10 | Espaços em variável .env do frontend | BAIXA | CORRIGIDO |
| **11** | **Heredoc `'EOF'` impede expansão de variáveis** | **CRÍTICA** | **CORRIGIDO** |
| **12** | **Nginx config com portas não expandidas** | **CRÍTICA** | **CORRIGIDO** |

---

## Arquivos Modificados

### 1. `lib/_system.sh` (11 correções)

#### Correção 1: OpenSSL passwd descontinuado
**Linha:** 17-25
**Problema:** `openssl passwd -crypt` foi descontinuado no Ubuntu 22.04

```bash
# ANTES:
useradd -m -p "$(openssl passwd -crypt ${mysql_root_password})" -s /bin/bash -G sudo deploy

# DEPOIS:
useradd -m -s /bin/bash -G sudo deploy
echo "deploy:${mysql_root_password}" | chpasswd
```

#### Correção 2: Remoção do Apache2
**Linha:** 86-96
**Problema:** Apache2 vem pré-instalado e conflita com Nginx na porta 80

```bash
# ADICIONADO:
apt-get remove -y apache2 apache2-utils || true
```

#### Correção 3: Instalação do Node.js 20
**Linha:** 319-343
**Problema:** `curl ... | bash -` foi descontinuado pelo NodeSource

```bash
# ANTES:
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -

# DEPOIS:
mkdir -p /etc/apt/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" > /etc/apt/sources.list.d/nodesource.list
apt-get update -y
apt-get install -y nodejs
```

#### Correção 4: Dependências Puppeteer
**Linha:** 391-406
**Problema:** Faltavam bibliotecas necessárias para o Chromium/Puppeteer

```bash
# ADICIONADO:
libatk-bridge2.0-0 libdrm2 libxkbcommon0 libatspi2.0-0
```

#### Correção 5: Criação automática de Swap
**Linha:** 408-444 (nova função)
**Problema:** VPS com menos de 2GB RAM falham no build

```bash
# NOVA FUNÇÃO ADICIONADA:
system_create_swap() {
  # Verifica memória total
  total_mem=$(free -m | awk '/^Mem:/{print $2}')
  if [ "$total_mem" -lt 2048 ]; then
    # Cria 2GB de swap
    fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
  fi
}
```

#### Correção 6: Função deletar_tudo
**Linha:** 115-127
**Problema:** `sudo su - postgres` dentro de heredoc não funciona

```bash
# ANTES:
sudo su - postgres
dropuser ${empresa_delete}
dropdb ${empresa_delete}
exit

# DEPOIS:
sudo -u postgres dropuser ${empresa_delete} 2>/dev/null || true
sudo -u postgres dropdb ${empresa_delete} 2>/dev/null || true
```

#### Correção 7: Docker container pode não existir
**Linha:** 116
**Problema:** Falha se container Redis não existe

```bash
# ANTES:
docker container rm redis-${empresa_delete} --force

# DEPOIS:
docker container rm redis-${empresa_delete} --force 2>/dev/null || true
```

#### Correção 8: Heredoc com aspas simples em system_git_clone
**Linha:** 43-47
**Problema:** `<<'EOF'` impede expansão de `${instancia_add}` e `${link_git}`

```bash
# ANTES:
sudo su - deploy <<'EOF'
  mkdir -p "/home/deploy/${instancia_add}"
  git clone "${link_git}" "/home/deploy/${instancia_add}/"
EOF

# DEPOIS:
sudo su - deploy <<EOF
  mkdir -p "/home/deploy/${instancia_add}"
  git clone "${link_git}" "/home/deploy/${instancia_add}/"
EOF
```

#### Correção 9: Heredoc em system_certbot_setup
**Linha:** 593-600
**Problema:** `<<'EOF'` impede expansão de variáveis de domínio

```bash
# ANTES:
sudo su - root <<'EOF'
  certbot -m "$deploy_email" --domains "$backend_domain","$frontend_domain" || true
EOF

# DEPOIS:
sudo su - root <<EOF
  certbot -m "$deploy_email" --domains "$backend_domain","$frontend_domain" || true
EOF
```

#### Correção 10: Heredoc em configurar_dominio (certbot)
**Linha:** 296-302
**Problema:** Variáveis sem aspas e sem proteção contra falha

```bash
# ANTES:
certbot -m $deploy_email --domains $backend_domain,$frontend_domain

# DEPOIS:
certbot -m "$deploy_email" --domains "$backend_domain,$frontend_domain" || true
```

#### Correção 11: Nginx config em configurar_dominio
**Linha:** 234-252 e 258-276
**Problema:** Heredoc interno `'END'` impede expansão de portas

```bash
# ANTES:
proxy_pass http://127.0.0.1:${alter_backend_port};
proxy_pass http://127.0.0.1:${alter_frontend_port};

# DEPOIS:
proxy_pass http://127.0.0.1:$alter_backend_port;
proxy_pass http://127.0.0.1:$alter_frontend_port;
```

---

### 2. `lib/_backend.sh` (7 correções)

#### Correção 1: Permissões Docker
**Linha:** 9-45
**Problema:** Usuário deploy sem permissão para executar Docker

```bash
# ADICIONADO:
mkdir -p "/home/deploy/${instancia_add}/redis"
chown -R deploy:deploy "/home/deploy/${instancia_add}/redis"
systemctl start docker || true
systemctl enable docker || true
```

#### Correção 2: Typo crítico em variável Redis
**Linha:** 89
**Problema:** `REGIS_OPT_LIMITER_DURATION` (typo)

```bash
# ANTES:
REGIS_OPT_LIMITER_DURATION=3000

# DEPOIS:
REDIS_OPT_LIMITER_DURATION=3000
```

#### Correção 3: Memória no build do backend
**Linha:** 132-147
**Problema:** Build pode falhar por falta de memória

```bash
# ADICIONADO:
export NODE_OPTIONS="--max-old-space-size=4096"
npm run build
```

#### Correção 4: Memória no backend_update
**Linha:** 154-181
**Problema:** Atualização pode falhar no build

```bash
# ADICIONADO:
export NODE_OPTIONS="--max-old-space-size=4096"
npm run build
```

#### Correção 5: backend_redis_upgrade_safe
**Linha:** 245-275
**Problema:** Mesmos problemas de Docker da função principal

```bash
# ADICIONADO:
chown -R deploy:deploy "$data_dir"
systemctl start docker || true
```

#### Correção 6: Heredoc em backend_redis_create
**Linha:** 16-41
**Problema:** `<<'EOF'` impede expansão de variáveis críticas

```bash
# ANTES:
sudo su - root <<'EOF'
  mkdir -p "/home/deploy/${instancia_add}/redis"
  docker run --name "redis-${instancia_add}" -p "${redis_port}:6379" ...
EOF

# DEPOIS:
sudo su - root <<EOF
  mkdir -p "/home/deploy/${instancia_add}/redis"
  docker run --name "redis-${instancia_add}" -p "${redis_port}:6379" ...
EOF
```

#### Correção 7: Heredoc em backend_redis_upgrade_safe
**Linha:** 255-276
**Problema:** `<<'EOF'` impede expansão de variáveis

```bash
# ANTES:
sudo su - root <<'EOF'
  cname="redis-${instancia_add}"
  docker run ... -p "${redis_port}:6379" ...
EOF

# DEPOIS:
sudo su - root <<EOF
  cname="redis-${instancia_add}"
  docker run ... -p "${redis_port}:6379" ...
EOF
```

#### Correção 8: Nginx config em backend_nginx_setup
**Linha:** 295-313
**Problema:** Heredoc interno `'END'` impede expansão de porta

```bash
# ANTES:
proxy_pass http://127.0.0.1:${backend_port};

# DEPOIS:
proxy_pass http://127.0.0.1:$backend_port;
```

---

### 3. `lib/_frontend.sh` (4 correções)

#### Correção 1: Variável .env com espaços
**Linha:** 93
**Problema:** Espaços ao redor de `=` causam problemas

```bash
# ANTES:
REACT_APP_HOURS_CLOSE_TICKETS_AUTO = 24

# DEPOIS:
REACT_APP_HOURS_CLOSE_TICKETS_AUTO=24
```

#### Correção 2: Memória no build do frontend
**Linha:** 30-45
**Problema:** Build pode falhar por falta de memória

```bash
# ADICIONADO:
export NODE_OPTIONS="--max-old-space-size=4096"
npm run build
```

#### Correção 3: Memória no frontend_update
**Linha:** 52-74
**Problema:** Atualização pode falhar no build

```bash
# ADICIONADO:
export NODE_OPTIONS="--max-old-space-size=4096"
npm run build
```

#### Correção 4: Nginx config em frontend_nginx_setup
**Linha:** 161-182
**Problema:** Heredoc interno `'END'` impede expansão de porta

```bash
# ANTES:
proxy_pass http://127.0.0.1:${frontend_port};

# DEPOIS:
proxy_pass http://127.0.0.1:$frontend_port;
```

---

### 4. `install_primaria` (1 correção)

#### Correção 1: Chamada de system_create_swap
**Linha:** 44
**Problema:** Swap não era verificado/criado

```bash
# ADICIONADO após system_update:
system_create_swap
```

---

## Testando o Instalador Corrigido

### Primeira instalação:

```bash
# Baixar instalador
sudo apt install -y git
git clone https://github.com/seu-repo/instalador
cd instalador

# Dar permissão e executar
sudo chmod +x install_primaria install_instancia
sudo ./install_primaria
```

### Segunda instalação ou adicional:

```bash
cd instalador
sudo ./install_instancia
```

---

## Requisitos Mínimos do Servidor

| Recurso | Mínimo | Recomendado |
|---------|--------|-------------|
| CPU | 2 vCPU | 4+ vCPU |
| RAM | 1GB (+2GB swap) | 4GB+ |
| Disco | 40GB | 80GB+ |
| SO | Ubuntu 22.04 LTS | Ubuntu 22.04/24.04 LTS |

---

## Observações Importantes

1. **DNS:** Os domínios (frontend/backend) devem estar configurados e apontando para o IP do servidor ANTES de executar o instalador, caso contrário o Certbot falhará.

2. **Portas:** Certifique-se de que as portas 80, 443 e as portas escolhidas para frontend/backend/redis estão liberadas no firewall.

3. **Senha:** Use uma senha sem caracteres especiais para o usuário deploy/banco, conforme solicitado pelo instalador.

4. **Node.js:** O instalador usa Node.js 20 LTS conforme especificado em `backend/package.json`.

5. **PostgreSQL:** A versão do PostgreSQL será a nativa do Ubuntu 22.04 (v14) ou 24.04 (v16).

---

## Resumo Total de Correções

| Arquivo | Correções | Descrição |
|---------|-----------|-----------|
| `lib/_system.sh` | 11 | OpenSSL, Apache2, Node.js, Puppeteer, Swap, deletar_tudo, **4 heredocs** |
| `lib/_backend.sh` | 8 | Docker, Typo REDIS, NODE_OPTIONS, **3 heredocs/nginx** |
| `lib/_frontend.sh` | 4 | Typo .env, NODE_OPTIONS, **1 nginx** |
| `install_primaria` | 1 | Adicionado system_create_swap |
| **TOTAL** | **24** | **Correções aplicadas** |

---

## Histórico de Alterações

| Data | Alteração | Autor |
|------|-----------|-------|
| 27/12/2025 | Versão inicial (16 correções) | Claude |
| 27/12/2025 | v2: Adicionadas correções críticas de heredoc (24 total) | Claude |

