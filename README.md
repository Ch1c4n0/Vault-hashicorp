# HashiCorp Vault local com Docker

Este projeto sobe um **HashiCorp Vault** local, com interface web, para guardar senhas e segredos (API keys, client secrets, senhas de banco, etc.) fora de arquivos `.env` em texto puro.

> **Importante:** esta configuração é para **laboratório/desenvolvimento local**. Ela usa HTTP sem TLS (`tls_disable = true`) e armazenamento em arquivo (`storage "file"`). Não publique a porta `8200` na internet e não use esta configuração exatamente assim em produção — veja a seção [10. Boas práticas de segurança](#10-boas-práticas-de-segurança).

Este guia foi escrito passo a passo, com uma ação por linha, para ser fácil de seguir mesmo se você nunca usou o Vault antes.

## Sumário

1. [Antes de começar](#1-antes-de-começar)
2. [Iniciar o Vault](#2-iniciar-o-vault)
3. [Inicializar e destravar (unseal)](#3-inicializar-e-destravar-unseal)
   - [3.4 Destravar automaticamente](#34-destravar-automaticamente-não-digitar-as-3-chaves-toda-vez)
4. [Ativar o cofre de senhas (KV)](#4-ativar-o-cofre-de-senhas-kv)
5. [Guardar e ler senhas](#5-guardar-e-ler-senhas)
6. [Dar acesso a uma APLICAÇÃO (menor privilégio)](#6-dar-acesso-a-uma-aplicação-menor-privilégio)
7. [Criar usuários (pessoas) para acessar o Vault](#7-criar-usuários-pessoas-para-acessar-o-vault)
8. [`docker compose exec` vs `docker exec` — nome do container](#8-docker-compose-exec-vs-docker-exec--nome-do-container)
9. [PowerShell vs Bash — referência rápida](#9-powershell-vs-bash--referência-rápida)
10. [Solução de problemas comuns](#10-solução-de-problemas-comuns)
11. [Parar, reiniciar e limpar](#11-parar-reiniciar-e-limpar)
12. [Boas práticas de segurança](#12-boas-práticas-de-segurança)

---

## 1. Antes de começar

Você precisa ter:

- Docker Desktop aberto e funcionando.
- Um terminal: PowerShell (Windows) ou Bash (Linux/macOS/WSL).
- Acesso a esta pasta (`Vault`).

O container criado por este projeto se chama **`local-vault`** — esse nome aparece em vários comandos abaixo.

## 2. Iniciar o Vault

Dentro desta pasta, execute:

```powershell
docker compose up -d --build
```

Confira se o container está de pé:

```powershell
docker compose ps
docker compose logs vault
```

Abra no navegador:

```text
http://localhost:8200
```

Você verá a tela inicial. Neste momento o Vault ainda está **selado** (travado). Isso é normal — ele começa assim sempre que os dados ainda não existem ou o container reinicia.

## 3. Inicializar e destravar (unseal)

### 3.1 Gerar as chaves (só na primeira vez)

```powershell
docker exec -it local-vault vault operator init -key-shares=5 -key-threshold=3
```

O resultado traz **5 Unseal Keys** e 1 **Initial Root Token**. Guarde tudo em um gerenciador de senhas.

> ⚠️ **Nunca** salve essas chaves em um arquivo dentro de uma pasta versionada no Git (nem em texto puro no computador, se puder evitar). Quem tiver 3 das 5 chaves + o Root Token tem controle total deste Vault.

### 3.2 Destravar (repita 3 vezes, com 3 chaves diferentes)

```powershell
docker exec -it local-vault vault operator unseal
```

Cole uma chave por execução. Depois da 3ª chave correta, confira:

```powershell
docker exec -it local-vault vault status
```

O campo `Sealed` deve estar `false`.

### 3.3 Pela interface web

1. Abra `http://localhost:8200`.
2. Cole uma **Unseal Key** por vez, no campo indicado, e clique em **Unseal** — repita 3 vezes.
3. Depois de destravado, escolha o método **Token**, cole o **Initial Root Token** e clique em **Sign In**.

### 3.4 Destravar automaticamente (não digitar as 3 chaves toda vez)

Se você reinicia o Docker com frequência e está cansado de repetir o passo 3.2 manualmente, este projeto já traz um segundo container — **`local-vault-unseal`** — que fica de olho no Vault e destrava sozinho sempre que ele estiver selado (depois de `docker restart`, reboot da máquina, `docker compose up` de novo, etc.).

> Isso **não** é o "Auto Unseal" nativo do Vault (que usa um serviço de nuvem como Azure Key Vault/AWS KMS e elimina as Shamir Keys por completo). É um jeito prático de automatizar o mesmo passo manual, guardando as chaves em um arquivo local `.env` em vez de digitá-las. Veja o trade-off de segurança na seção 12.

**Como ativar:**

1. Copie o arquivo de exemplo:

   ```powershell
   Copy-Item .env.example .env
   ```

2. Abra o `.env` e cole as 3 Unseal Keys reais (as mesmas da seção 3.1):

   ```env
   VAULT_UNSEAL_KEY_1="cole a chave 1 aqui"
   VAULT_UNSEAL_KEY_2="cole a chave 2 aqui"
   VAULT_UNSEAL_KEY_3="cole a chave 3 aqui"
   ```

3. Suba a stack novamente:

   ```powershell
   docker compose up -d --build
   ```

4. Confirme que funcionou:

   ```powershell
   docker logs local-vault-unseal
   docker exec local-vault vault status
   ```

   Nos logs deve aparecer `Vault destravado com sucesso.`, e o `status` deve mostrar `Sealed: false` — sem você ter digitado nada.

O `.env` nunca é commitado (está no `.gitignore`). Se as chaves nele estiverem erradas ou vazias, o `docker compose up` já falha com um aviso claro (`defina VAULT_UNSEAL_KEY_1 no arquivo .env`), em vez de subir quebrado silenciosamente.

## 4. Ativar o cofre de senhas (KV)

Defina o token administrativo **nesta sessão do terminal** (veja a seção 9 sobre por que isso importa):

```powershell
$env:VAULT_TOKEN = "COLE_AQUI_O_INITIAL_ROOT_TOKEN"
```

Ative o motor de segredos KV versão 2:

```powershell
docker exec -e VAULT_TOKEN=$env:VAULT_TOKEN local-vault vault secrets enable -path=secret kv-v2
```

Se aparecer "path is already in use", já foi criado — pode seguir.

**Pela interface web:** menu **Secrets Engines** → **Enable new engine** → escolha **KV** → **Path**: `secret` → **Enable Engine**.

## 5. Guardar e ler senhas

Gravar um segredo (exemplo: credenciais de um banco):

```powershell
docker exec -e VAULT_TOKEN=$env:VAULT_TOKEN local-vault vault kv put secret/desenvolvimento banco_usuario="app_user" banco_senha="Troque_Esta_Senha"
```

Ler o segredo inteiro:

```powershell
docker exec -e VAULT_TOKEN=$env:VAULT_TOKEN local-vault vault kv get secret/desenvolvimento
```

Ler só um campo:

```powershell
docker exec -e VAULT_TOKEN=$env:VAULT_TOKEN local-vault vault kv get -field=banco_senha secret/desenvolvimento
```

Para atualizar, rode o mesmo `kv put` com o novo valor — o Vault guarda um histórico de versões.

**Pela interface web:**

1. **Secrets Engines** → `secret/` → **Create secret**.
2. **Path**: `desenvolvimento`.
3. Adicione os campos (ex.: `banco_usuario`, `banco_senha`) com **Add**.
4. **Save**.
5. Para ver depois: abra o segredo → **Reveal values** (ele fica escondido por padrão, de propósito).

O que você cria no terminal aparece na web, e o que você cria na web aparece no terminal — é o mesmo cofre.

## 6. Dar acesso a uma APLICAÇÃO (menor privilégio)

Uma aplicação **nunca** deve usar o Root Token. Ela deve receber acesso **só de leitura** e **só ao caminho que precisa**.

### 6.1 Criar a política (ACL Policy)

Uma política descreve o que é permitido. Por padrão, o Vault **nega tudo** — a política só libera o que você escrever.

**Pela interface web:**

1. Menu **Policies** → **ACL Policies** → **Create ACL policy**.
2. **Name**: `app-security-m365-readonly` (troque pelo nome do seu app).
3. No editor, cole (ajuste o nome da engine e do caminho para o seu caso):

```hcl
# Permite só LER os segredos deste caminho específico
path "secret/data/app-security-m365" {
  capabilities = ["read"]
}

# Permite listar/ler os metadados (necessário para o app enxergar o segredo)
path "secret/metadata/app-security-m365" {
  capabilities = ["read", "list"]
}
```

4. **Create policy**.

**Pela linha de comando** (equivalente ao passo acima):

```powershell
docker exec -e VAULT_TOKEN=$env:VAULT_TOKEN local-vault vault policy write app-security-m365-readonly - <<'EOF'
path "secret/data/app-security-m365" {
  capabilities = ["read"]
}
path "secret/metadata/app-security-m365" {
  capabilities = ["read", "list"]
}
EOF
```

### 6.2 Opção A — Token direto (mais simples)

Gera um token já com a política anexada, sem precisar de usuário/senha:

```powershell
docker exec -e VAULT_TOKEN=$env:VAULT_TOKEN local-vault vault token create -policy="app-security-m365-readonly" -no-default-policy -ttl=720h
```

- `-ttl=720h` → o token expira em 30 dias (ajuste como quiser).
- Copie o `token` do resultado e coloque no `.env` da aplicação, ex.: `VAULT_TOKEN="hvs...."`.

### 6.3 Opção B — AppRole (recomendado para aplicações)

O **AppRole** é o método pensado especificamente para autenticação de máquina/aplicação — ele gera um `role_id` (fixo, pode ficar no código) e um `secret_id` (sensível, fica só no `.env`), em vez de um único token fixo.

1. Ativar o método (só uma vez):

```powershell
docker exec -e VAULT_TOKEN=$env:VAULT_TOKEN local-vault vault auth enable approle
```

Se disser "path is already in use", já está ativo.

2. Criar o "papel" (role) da aplicação, ligado à política criada em 6.1:

```powershell
docker exec -e VAULT_TOKEN=$env:VAULT_TOKEN local-vault vault write auth/approle/role/app-security-m365 token_policies="app-security-m365-readonly" token_ttl=1h token_max_ttl=4h secret_id_ttl=0 token_num_uses=0
```

3. Pegar o `role_id` (fixo):

```powershell
docker exec -e VAULT_TOKEN=$env:VAULT_TOKEN local-vault vault read auth/approle/role/app-security-m365/role-id
```

4. Gerar um `secret_id` (sensível, tratar como senha):

```powershell
docker exec -e VAULT_TOKEN=$env:VAULT_TOKEN local-vault vault write -f auth/approle/role/app-security-m365/secret-id
```

5. Colocar os dois no `.env` da aplicação:

```env
VAULT_ROLE_ID="<valor do role_id>"
VAULT_SECRET_ID="<valor do secret_id>"
```

A aplicação troca esses dois valores por um token temporário toda vez que inicia — se o `secret_id` vazar, você revoga só ele, sem mexer no resto.

**Pela interface web:** **Access** → **Auth Methods** → **Enable new method** → **AppRole** → depois de habilitado, clique nele → **Create role** para preencher os mesmos campos do passo 2.

## 7. Criar usuários (pessoas) para acessar o Vault

Diferente do AppRole (para aplicações), aqui é login humano com **usuário e senha**.

### 7.1 Ativar o método de login por usuário/senha (só uma vez)

```powershell
docker exec -e VAULT_TOKEN=$env:VAULT_TOKEN local-vault vault auth enable userpass
```

### 7.2 Usuário com acesso limitado (recomendado no dia a dia)

```powershell
docker exec -e VAULT_TOKEN=$env:VAULT_TOKEN local-vault vault write auth/userpass/users/marcelo password="TrocarPorSenhaForte123!" policies="app-security-m365-readonly"
```

Testar o login:

```powershell
docker exec -it local-vault vault login -method=userpass username=marcelo password="TrocarPorSenhaForte123!"
```

**Pela interface web:** **Access** → **Auth Methods** → `userpass` → **Create user** → preencha **Username**, **Password** e, em **Generated Token's Policies**, o nome da política (ex.: `app-security-m365-readonly`) → **Save**.

Para entrar com esse usuário depois: faça **Sign out** do Root Token, troque o **Method** de `Token` para `Username` na tela de login, e entre com usuário/senha.

### 7.3 Usuário com acesso total (equivalente a "root")

O Vault tem uma política especial reservada chamada **`root`**, com acesso total e irrestrito — o mesmo poder do Initial Root Token, só que entregue por usuário/senha:

```powershell
docker exec -e VAULT_TOKEN=$env:VAULT_TOKEN local-vault vault write auth/userpass/users/marcelo password="TrocarPorSenhaForte123!" policies="root"
```

**Pela interface web:** mesmo caminho do item 7.2, mas em **Generated Token's Policies** digite `root`.

> ⚠️ **Use com cautela.** Dar `root` a um usuário do dia a dia anula toda a granularidade das políticas. Prefira criar uma política **admin** customizada (acesso amplo, mas não o `root` literal), reservando o `root`/Initial Root Token só para emergências ("break-glass"):
>
> ```hcl
> # admin.hcl — acesso administrativo amplo, mas nomeado e auditável
> path "*" {
>   capabilities = ["create", "read", "update", "delete", "list", "sudo"]
> }
> ```
>
> ```powershell
> docker exec -e VAULT_TOKEN=$env:VAULT_TOKEN local-vault vault policy write admin - <<'EOF'
> path "*" {
>   capabilities = ["create", "read", "update", "delete", "list", "sudo"]
> }
> EOF
> ```

## 8. `docker compose exec` vs `docker exec` — nome do container

Há duas formas de mandar comandos para o Vault, e elas se comportam diferente:

| | `docker compose exec vault ...` | `docker exec local-vault ...` |
|---|---|---|
| Precisa estar na pasta certa (`D:\Vault`)? | **Sim** | Não — funciona de qualquer pasta |
| Nome usado | Nome do **serviço** no `docker-compose.yml` (`vault`) | Nome do **container** (`local-vault`) |
| Erro comum se usar na pasta errada | `service "vault" is not running` | não acontece |

Por isso este guia usa `docker exec local-vault ...` na maioria dos comandos — evita o erro de "pasta errada".

## 9. PowerShell vs Bash — referência rápida

| Ação | PowerShell | Bash |
|---|---|---|
| Definir variável de ambiente | `$env:VAULT_TOKEN = "valor"` | `export VAULT_TOKEN="valor"` |
| Ler variável de ambiente | `$env:VAULT_TOKEN` | `$VAULT_TOKEN` |
| Passar variável para o `docker exec` | `-e VAULT_TOKEN=$env:VAULT_TOKEN` | `-e VAULT_TOKEN="$VAULT_TOKEN"` |

Misturar os dois é o erro mais comum: `export` não existe no PowerShell, e `$env:VAULT_TOKEN` não existe no Bash. Além disso, **a variável só existe no terminal onde foi definida** — se você abrir uma aba/janela nova, precisa definir de novo.

## 10. Solução de problemas comuns

| Erro | Causa provável | Solução |
|---|---|---|
| `service "vault" is not running` | Comando `docker compose exec` rodado fora de `D:\Vault` | `cd D:\Vault` antes, ou use `docker exec local-vault ...` (seção 8) |
| `403 permission denied` / `invalid token` | `VAULT_TOKEN` vazio, errado, ou com sintaxe do shell trocada | Confirme com `echo $env:VAULT_TOKEN` (PowerShell) e redefina; confira a seção 9 |
| `Path can't be blank` (na web, ao criar secret) | Campo **Path** não preenchido | Digite um nome, ex.: `desenvolvimento` |
| Comandos não fazem nada / tudo dá erro de conexão | Vault ainda **selado** após reiniciar o container | Rode `vault status`; se `Sealed: true`, destrave com 3 chaves (seção 3.2) ou ative o auto-unseal (seção 3.4) |
| `export: The term 'export' is not recognized...` | Comando de Bash digitado no PowerShell | Use `$env:VAULT_TOKEN = "valor"` (seção 9) |

## 11. Parar, reiniciar e limpar

Parar sem apagar dados:

```powershell
docker compose down
```

Iniciar de novo:

```powershell
docker compose up -d
```

Os dados ficam no volume Docker `vault-data` — sobrevivem ao `down`/`up`. Depois de reiniciar, o Vault pode voltar selado (seção 3.2), ou já vir destravado sozinho se o auto-unseal (seção 3.4) estiver ativo.

**Apagar tudo** (dados e segredos deste Vault local):

```powershell
docker compose down -v
```

> ⚠️ Depois da limpeza total, será preciso inicializar de novo (seção 3.1) e guardar chaves novas.

## 12. Boas práticas de segurança

- Não use o `Initial Root Token` (nem a política `root`) em aplicações — use AppRole (seção 6.3) ou um token com política restrita (seção 6.2).
- Nunca salve Unseal Keys, Root Token, `role_id`/`secret_id` ou senhas em arquivos dentro de pastas versionadas no Git.
- Se algum desses valores foi colado em um chat, e-mail ou qualquer lugar fora do seu controle, considere-o exposto — gere novos (reinicialize o Vault ou rotacione o `secret_id`/token).
- Crie uma política por aplicação, liberando **só** os caminhos que ela realmente usa.
- Use HTTPS/TLS antes de deixar o Vault acessível por outra máquina (esta configuração usa `tls_disable = true`, só para localhost).
- Faça backup protegido do volume `/vault/data`.
- Teste sempre primeiro com senhas descartáveis, nunca com credenciais reais de produção.
- **Sobre o auto-unseal da seção 3.4:** ele guarda as 3 Unseal Keys em texto puro no arquivo `.env` local. Isso reduz a proteção que o esquema Shamir (3 de 5 chaves, guardadas separadamente) foi desenhado para dar — quem tiver acesso a esse `.env` já destrava o Vault sozinho. Para um ambiente que não seja só o seu laboratório local, prefira o **Auto Unseal nativo** do Vault com um serviço de nuvem (ex.: Azure Key Vault, AWS KMS), que elimina as Shamir Keys por completo em vez de só automatizar o envio delas.
