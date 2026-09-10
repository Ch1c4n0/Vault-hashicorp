<p align="center">
  <img alt="HashiCorp Vault" src="https://img.shields.io/badge/HashiCorp%20Vault-000000?style=for-the-badge&logo=vault&logoColor=white" />
  <img alt="Docker" src="https://img.shields.io/badge/Docker-2496ED?style=for-the-badge&logo=docker&logoColor=white" />
  <img alt="IBM" src="https://img.shields.io/badge/IBM-052FAD?style=for-the-badge&logo=ibm&logoColor=white" />
</p>

<p align="center">
  <a href="#english"><b>🇺🇸 English</b></a> &nbsp;|&nbsp; <a href="#português"><b>🇧🇷 Português</b></a>
</p>

---

# HashiCorp Vault — Local Docker Setup

<a id="english"></a>
## English

This project spins up a local **HashiCorp Vault**, with a web UI, to store passwords and secrets (API keys, client secrets, database passwords, etc.) outside of plain-text `.env` files.

> **Important:** this setup is for **local lab/development use**. It uses HTTP without TLS (`tls_disable = true`) and file-based storage (`storage "file"`). Do not expose port `8200` to the internet and do not use this exact setup in production — see [12. Security best practices](#12-security-best-practices).

This guide is written step by step, one action per line, so it's easy to follow even if you've never used Vault before.

### Table of Contents

1. [Before you start](#1-before-you-start)
2. [Start Vault](#2-start-vault)
3. [Initialize and unseal](#3-initialize-and-unseal)
   - [3.4 Automatic unseal](#34-automatic-unseal-stop-typing-the-3-keys-every-time)
4. [Enable the secrets vault (KV)](#4-enable-the-secrets-vault-kv)
5. [Store and read secrets](#5-store-and-read-secrets)
6. [Grant access to an APPLICATION (least privilege)](#6-grant-access-to-an-application-least-privilege)
7. [Create users (people) to access Vault](#7-create-users-people-to-access-vault)
8. [`docker compose exec` vs `docker exec` — container name](#8-docker-compose-exec-vs-docker-exec--container-name)
9. [PowerShell vs Bash — quick reference](#9-powershell-vs-bash--quick-reference)
10. [Common troubleshooting](#10-common-troubleshooting)
11. [Stop, restart and clean up](#11-stop-restart-and-clean-up)
12. [Security best practices](#12-security-best-practices)

---

### 1. Before you start

You need:

- Docker Desktop open and running.
- A terminal: PowerShell (Windows) or Bash (Linux/macOS/WSL).
- Access to this folder (`Vault`).

The container created by this project is named **`local-vault`** — this name shows up in most of the commands below.

### 2. Start Vault

From inside this folder, run:

```powershell
docker compose up -d --build
```

Check that the container is up:

```powershell
docker compose ps
docker compose logs vault
```

Open in your browser:

```text
http://localhost:8200
```

You'll see the initial screen. At this point Vault is still **sealed** (locked). This is normal — it always starts this way when data doesn't exist yet, or when the container restarts.

### 3. Initialize and unseal

#### 3.1 Generate the keys (first time only)

```powershell
docker exec -it local-vault vault operator init -key-shares=5 -key-threshold=3
```

The result gives you **5 Unseal Keys** and 1 **Initial Root Token**. Save everything in a password manager.

> ⚠️ **Never** save these keys in a file inside a folder tracked by Git (nor in plain text on your computer, if you can avoid it). Whoever holds 3 of the 5 keys + the Root Token has full control of this Vault.

#### 3.2 Unseal (repeat 3 times, with 3 different keys)

```powershell
docker exec -it local-vault vault operator unseal
```

Paste one key per run. After the 3rd correct key, check:

```powershell
docker exec -it local-vault vault status
```

The `Sealed` field should read `false`.

#### 3.3 Via the web UI

1. Open `http://localhost:8200`.
2. Paste one **Unseal Key** at a time in the field shown, and click **Unseal** — repeat 3 times.
3. Once unsealed, choose the **Token** method, paste the **Initial Root Token**, and click **Sign In**.

#### 3.4 Automatic unseal (stop typing the 3 keys every time)

If you restart Docker often and are tired of repeating step 3.2 by hand, this project already ships a second container — **`local-vault-unseal`** — that watches Vault and unseals it automatically whenever it's sealed (after `docker restart`, a machine reboot, `docker compose up` again, etc.).

> This is **not** Vault's native "Auto Unseal" (which uses a cloud service like Azure Key Vault/AWS KMS and removes Shamir Keys entirely). It's a practical way to automate the same manual step, by storing the keys in a local `.env` file instead of typing them. See the security trade-off in section 12.

**How to enable it:**

1. Copy the example file:

   ```powershell
   Copy-Item .env.example .env
   ```

2. Open `.env` and paste the 3 real Unseal Keys (the same ones from section 3.1):

   ```env
   VAULT_UNSEAL_KEY_1="paste key 1 here"
   VAULT_UNSEAL_KEY_2="paste key 2 here"
   VAULT_UNSEAL_KEY_3="paste key 3 here"
   ```

3. Bring the stack up again:

   ```powershell
   docker compose up -d --build
   ```

4. Confirm it worked:

   ```powershell
   docker logs local-vault-unseal
   docker exec local-vault vault status
   ```

   The logs should show `Vault destravado com sucesso.` (the container's own log message), and `status` should show `Sealed: false` — without you typing anything.

`.env` is never committed (it's in `.gitignore`). If the keys in it are wrong or empty, `docker compose up` already fails with a clear message (`defina VAULT_UNSEAL_KEY_1 no arquivo .env`), instead of coming up silently broken.

### 4. Enable the secrets vault (KV)

Set the admin token **for this terminal session** (see section 9 for why this matters):

```powershell
$env:VAULT_TOKEN = "PASTE_THE_INITIAL_ROOT_TOKEN_HERE"
```

Enable the KV version 2 secrets engine:

```powershell
docker exec -e VAULT_TOKEN=$env:VAULT_TOKEN local-vault vault secrets enable -path=secret kv-v2
```

If it says "path is already in use", it was already created — you can continue.

**Via the web UI:** **Secrets Engines** menu → **Enable new engine** → choose **KV** → **Path**: `secret` → **Enable Engine**.

### 5. Store and read secrets

Write a secret (example: database credentials):

```powershell
docker exec -e VAULT_TOKEN=$env:VAULT_TOKEN local-vault vault kv put secret/desenvolvimento banco_usuario="app_user" banco_senha="Change_This_Password"
```

Read the whole secret:

```powershell
docker exec -e VAULT_TOKEN=$env:VAULT_TOKEN local-vault vault kv get secret/desenvolvimento
```

Read a single field:

```powershell
docker exec -e VAULT_TOKEN=$env:VAULT_TOKEN local-vault vault kv get -field=banco_senha secret/desenvolvimento
```

To update it, run the same `kv put` command with the new value — Vault keeps a version history.

**Via the web UI:**

1. **Secrets Engines** → `secret/` → **Create secret**.
2. **Path**: `desenvolvimento`.
3. Add the fields (e.g. `banco_usuario`, `banco_senha`) with **Add**.
4. **Save**.
5. To view it later: open the secret → **Reveal values** (it's hidden by default, on purpose).

What you create in the terminal shows up on the web, and what you create on the web shows up in the terminal — it's the same vault.

### 6. Grant access to an APPLICATION (least privilege)

An application should **never** use the Root Token. It should get access that's **read-only** and **scoped to only the path it needs**.

#### 6.1 Create the policy (ACL Policy)

A policy describes what's allowed. By default, Vault **denies everything** — the policy only opens up what you write.

**Via the web UI:**

1. **Policies** menu → **ACL Policies** → **Create ACL policy**.
2. **Name**: `app-security-m365-readonly` (replace with your app's name).
3. In the editor, paste (adjust the engine name and path to your case):

```hcl
# Allow only READING secrets at this specific path
path "secret/data/app-security-m365" {
  capabilities = ["read"]
}

# Allow listing/reading metadata (needed so the app can see the secret)
path "secret/metadata/app-security-m365" {
  capabilities = ["read", "list"]
}
```

4. **Create policy**.

**Via the command line** (equivalent to the step above):

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

#### 6.2 Option A — Direct token (simplest)

Generates a token with the policy already attached, no username/password needed:

```powershell
docker exec -e VAULT_TOKEN=$env:VAULT_TOKEN local-vault vault token create -policy="app-security-m365-readonly" -no-default-policy -ttl=720h
```

- `-ttl=720h` → the token expires in 30 days (adjust as you like).
- Copy the `token` from the result and put it in the application's `.env`, e.g.: `VAULT_TOKEN="hvs...."`.

#### 6.3 Option B — AppRole (recommended for applications)

**AppRole** is the method designed specifically for machine/application authentication — it generates a `role_id` (fixed, can live in code) and a `secret_id` (sensitive, only lives in `.env`), instead of a single fixed token.

1. Enable the method (only once):

```powershell
docker exec -e VAULT_TOKEN=$env:VAULT_TOKEN local-vault vault auth enable approle
```

If it says "path is already in use", it's already enabled.

2. Create the application's "role", linked to the policy created in 6.1:

```powershell
docker exec -e VAULT_TOKEN=$env:VAULT_TOKEN local-vault vault write auth/approle/role/app-security-m365 token_policies="app-security-m365-readonly" token_ttl=1h token_max_ttl=4h secret_id_ttl=0 token_num_uses=0
```

3. Get the `role_id` (fixed):

```powershell
docker exec -e VAULT_TOKEN=$env:VAULT_TOKEN local-vault vault read auth/approle/role/app-security-m365/role-id
```

4. Generate a `secret_id` (sensitive, treat like a password):

```powershell
docker exec -e VAULT_TOKEN=$env:VAULT_TOKEN local-vault vault write -f auth/approle/role/app-security-m365/secret-id
```

5. Put both in the application's `.env`:

```env
VAULT_ROLE_ID="<value of role_id>"
VAULT_SECRET_ID="<value of secret_id>"
```

The application exchanges these two values for a temporary token every time it starts — if the `secret_id` leaks, you only revoke that one, without touching anything else.

**Via the web UI:** **Access** → **Auth Methods** → **Enable new method** → **AppRole** → once enabled, click on it → **Create role** to fill in the same fields as step 2.

### 7. Create users (people) to access Vault

Unlike AppRole (for applications), this is a human login with **username and password**.

#### 7.1 Enable the username/password login method (only once)

```powershell
docker exec -e VAULT_TOKEN=$env:VAULT_TOKEN local-vault vault auth enable userpass
```

#### 7.2 User with limited access (recommended for everyday use)

```powershell
docker exec -e VAULT_TOKEN=$env:VAULT_TOKEN local-vault vault write auth/userpass/users/marcelo password="ChangeToAStrongPassword123!" policies="app-security-m365-readonly"
```

Test the login:

```powershell
docker exec -it local-vault vault login -method=userpass username=marcelo password="ChangeToAStrongPassword123!"
```

**Via the web UI:** **Access** → **Auth Methods** → `userpass` → **Create user** → fill in **Username**, **Password**, and, under **Generated Token's Policies**, the policy name (e.g. `app-security-m365-readonly`) → **Save**.

To log in with that user afterward: **Sign out** of the Root Token, switch the **Method** from `Token` to `Username` on the login screen, and log in with username/password.

#### 7.3 User with full access (equivalent to "root")

Vault has a special, reserved policy called **`root`**, with full, unrestricted access — the same power as the Initial Root Token, just delivered via username/password:

```powershell
docker exec -e VAULT_TOKEN=$env:VAULT_TOKEN local-vault vault write auth/userpass/users/marcelo password="ChangeToAStrongPassword123!" policies="root"
```

**Via the web UI:** same path as item 7.2, but under **Generated Token's Policies** type `root`.

> ⚠️ **Use with caution.** Giving `root` to a day-to-day user defeats the whole point of granular policies. Prefer creating a custom **admin** policy (broad access, but not the literal `root`), reserving the `root`/Initial Root Token for emergencies only ("break-glass"):
>
> ```hcl
> # admin.hcl — broad administrative access, but named and auditable
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

### 8. `docker compose exec` vs `docker exec` — container name

There are two ways to send commands to Vault, and they behave differently:

| | `docker compose exec vault ...` | `docker exec local-vault ...` |
|---|---|---|
| Must be in the right folder (`D:\Vault`)? | **Yes** | No — works from any folder |
| Name used | The **service** name in `docker-compose.yml` (`vault`) | The **container** name (`local-vault`) |
| Common error if used in the wrong folder | `service "vault" is not running` | doesn't happen |

That's why this guide uses `docker exec local-vault ...` for most commands — it avoids the "wrong folder" error.

### 9. PowerShell vs Bash — quick reference

| Action | PowerShell | Bash |
|---|---|---|
| Set environment variable | `$env:VAULT_TOKEN = "value"` | `export VAULT_TOKEN="value"` |
| Read environment variable | `$env:VAULT_TOKEN` | `$VAULT_TOKEN` |
| Pass variable to `docker exec` | `-e VAULT_TOKEN=$env:VAULT_TOKEN` | `-e VAULT_TOKEN="$VAULT_TOKEN"` |

Mixing the two is the most common mistake: `export` doesn't exist in PowerShell, and `$env:VAULT_TOKEN` doesn't exist in Bash. Also, **the variable only exists in the terminal where it was defined** — if you open a new tab/window, you need to set it again.

### 10. Common troubleshooting

| Error | Likely cause | Fix |
|---|---|---|
| `service "vault" is not running` | `docker compose exec` was run outside `D:\Vault` | `cd D:\Vault` first, or use `docker exec local-vault ...` (section 8) |
| `403 permission denied` / `invalid token` | `VAULT_TOKEN` is empty, wrong, or has the wrong shell syntax | Check with `echo $env:VAULT_TOKEN` (PowerShell) and reset it; see section 9 |
| `Path can't be blank` (on the web, when creating a secret) | **Path** field left empty | Type a name, e.g. `desenvolvimento` |
| Commands do nothing / everything gives a connection error | Vault is still **sealed** after the container restarted | Run `vault status`; if `Sealed: true`, unseal with 3 keys (section 3.2) or enable auto-unseal (section 3.4) |
| `export: The term 'export' is not recognized...` | Bash command typed into PowerShell | Use `$env:VAULT_TOKEN = "value"` (section 9) |

### 11. Stop, restart and clean up

Stop without deleting data:

```powershell
docker compose down
```

Start it again:

```powershell
docker compose up -d
```

Data lives in the `vault-data` Docker volume — it survives `down`/`up`. After restarting, Vault might come back sealed (section 3.2), or already unsealed on its own if auto-unseal (section 3.4) is enabled.

**Delete everything** (data and secrets in this local Vault):

```powershell
docker compose down -v
```

> ⚠️ After a full cleanup, you'll need to initialize again (section 3.1) and save new keys.

### 12. Security best practices

- Don't use the `Initial Root Token` (or the `root` policy) in applications — use AppRole (section 6.3) or a token with a restricted policy (section 6.2).
- Never save Unseal Keys, Root Token, `role_id`/`secret_id`, or passwords in files inside folders tracked by Git.
- If any of these values was pasted into a chat, email, or anywhere outside your control, consider it exposed — generate new ones (reinitialize Vault or rotate the `secret_id`/token).
- Create one policy per application, opening up **only** the paths it actually uses.
- Use HTTPS/TLS before making Vault reachable from another machine (this setup uses `tls_disable = true`, localhost only).
- Keep a protected backup of the `/vault/data` volume.
- Always test first with throwaway passwords, never with real production credentials.
- **About the auto-unseal in section 3.4:** it stores the 3 Unseal Keys in plain text in the local `.env` file. This reduces the protection the Shamir scheme (3 of 5 keys, kept separately) was designed to give — whoever has access to that `.env` can unseal Vault on their own. For any environment beyond your local lab, prefer Vault's **native Auto Unseal** with a cloud service (e.g., Azure Key Vault, AWS KMS), which removes Shamir Keys entirely instead of just automating how they're fed in.

---

<a id="português"></a>
## Português

Este projeto sobe um **HashiCorp Vault** local, com interface web, para guardar senhas e segredos (API keys, client secrets, senhas de banco, etc.) fora de arquivos `.env` em texto puro.

> **Importante:** esta configuração é para **laboratório/desenvolvimento local**. Ela usa HTTP sem TLS (`tls_disable = true`) e armazenamento em arquivo (`storage "file"`). Não publique a porta `8200` na internet e não use esta configuração exatamente assim em produção — veja a seção [12. Boas práticas de segurança](#12-boas-práticas-de-segurança).

Este guia foi escrito passo a passo, com uma ação por linha, para ser fácil de seguir mesmo se você nunca usou o Vault antes.

### Sumário

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

### 1. Antes de começar

Você precisa ter:

- Docker Desktop aberto e funcionando.
- Um terminal: PowerShell (Windows) ou Bash (Linux/macOS/WSL).
- Acesso a esta pasta (`Vault`).

O container criado por este projeto se chama **`local-vault`** — esse nome aparece em vários comandos abaixo.

### 2. Iniciar o Vault

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

### 3. Inicializar e destravar (unseal)

#### 3.1 Gerar as chaves (só na primeira vez)

```powershell
docker exec -it local-vault vault operator init -key-shares=5 -key-threshold=3
```

O resultado traz **5 Unseal Keys** e 1 **Initial Root Token**. Guarde tudo em um gerenciador de senhas.

> ⚠️ **Nunca** salve essas chaves em um arquivo dentro de uma pasta versionada no Git (nem em texto puro no computador, se puder evitar). Quem tiver 3 das 5 chaves + o Root Token tem controle total deste Vault.

#### 3.2 Destravar (repita 3 vezes, com 3 chaves diferentes)

```powershell
docker exec -it local-vault vault operator unseal
```

Cole uma chave por execução. Depois da 3ª chave correta, confira:

```powershell
docker exec -it local-vault vault status
```

O campo `Sealed` deve estar `false`.

#### 3.3 Pela interface web

1. Abra `http://localhost:8200`.
2. Cole uma **Unseal Key** por vez, no campo indicado, e clique em **Unseal** — repita 3 vezes.
3. Depois de destravado, escolha o método **Token**, cole o **Initial Root Token** e clique em **Sign In**.

#### 3.4 Destravar automaticamente (não digitar as 3 chaves toda vez)

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

### 4. Ativar o cofre de senhas (KV)

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

### 5. Guardar e ler senhas

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

### 6. Dar acesso a uma APLICAÇÃO (menor privilégio)

Uma aplicação **nunca** deve usar o Root Token. Ela deve receber acesso **só de leitura** e **só ao caminho que precisa**.

#### 6.1 Criar a política (ACL Policy)

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

#### 6.2 Opção A — Token direto (mais simples)

Gera um token já com a política anexada, sem precisar de usuário/senha:

```powershell
docker exec -e VAULT_TOKEN=$env:VAULT_TOKEN local-vault vault token create -policy="app-security-m365-readonly" -no-default-policy -ttl=720h
```

- `-ttl=720h` → o token expira em 30 dias (ajuste como quiser).
- Copie o `token` do resultado e coloque no `.env` da aplicação, ex.: `VAULT_TOKEN="hvs...."`.

#### 6.3 Opção B — AppRole (recomendado para aplicações)

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

### 7. Criar usuários (pessoas) para acessar o Vault

Diferente do AppRole (para aplicações), aqui é login humano com **usuário e senha**.

#### 7.1 Ativar o método de login por usuário/senha (só uma vez)

```powershell
docker exec -e VAULT_TOKEN=$env:VAULT_TOKEN local-vault vault auth enable userpass
```

#### 7.2 Usuário com acesso limitado (recomendado no dia a dia)

```powershell
docker exec -e VAULT_TOKEN=$env:VAULT_TOKEN local-vault vault write auth/userpass/users/marcelo password="TrocarPorSenhaForte123!" policies="app-security-m365-readonly"
```

Testar o login:

```powershell
docker exec -it local-vault vault login -method=userpass username=marcelo password="TrocarPorSenhaForte123!"
```

**Pela interface web:** **Access** → **Auth Methods** → `userpass` → **Create user** → preencha **Username**, **Password** e, em **Generated Token's Policies**, o nome da política (ex.: `app-security-m365-readonly`) → **Save**.

Para entrar com esse usuário depois: faça **Sign out** do Root Token, troque o **Method** de `Token` para `Username` na tela de login, e entre com usuário/senha.

#### 7.3 Usuário com acesso total (equivalente a "root")

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

### 8. `docker compose exec` vs `docker exec` — nome do container

Há duas formas de mandar comandos para o Vault, e elas se comportam diferente:

| | `docker compose exec vault ...` | `docker exec local-vault ...` |
|---|---|---|
| Precisa estar na pasta certa (`D:\Vault`)? | **Sim** | Não — funciona de qualquer pasta |
| Nome usado | Nome do **serviço** no `docker-compose.yml` (`vault`) | Nome do **container** (`local-vault`) |
| Erro comum se usar na pasta errada | `service "vault" is not running` | não acontece |

Por isso este guia usa `docker exec local-vault ...` na maioria dos comandos — evita o erro de "pasta errada".

### 9. PowerShell vs Bash — referência rápida

| Ação | PowerShell | Bash |
|---|---|---|
| Definir variável de ambiente | `$env:VAULT_TOKEN = "valor"` | `export VAULT_TOKEN="valor"` |
| Ler variável de ambiente | `$env:VAULT_TOKEN` | `$VAULT_TOKEN` |
| Passar variável para o `docker exec` | `-e VAULT_TOKEN=$env:VAULT_TOKEN` | `-e VAULT_TOKEN="$VAULT_TOKEN"` |

Misturar os dois é o erro mais comum: `export` não existe no PowerShell, e `$env:VAULT_TOKEN` não existe no Bash. Além disso, **a variável só existe no terminal onde foi definida** — se você abrir uma aba/janela nova, precisa definir de novo.

### 10. Solução de problemas comuns

| Erro | Causa provável | Solução |
|---|---|---|
| `service "vault" is not running` | Comando `docker compose exec` rodado fora de `D:\Vault` | `cd D:\Vault` antes, ou use `docker exec local-vault ...` (seção 8) |
| `403 permission denied` / `invalid token` | `VAULT_TOKEN` vazio, errado, ou com sintaxe do shell trocada | Confirme com `echo $env:VAULT_TOKEN` (PowerShell) e redefina; confira a seção 9 |
| `Path can't be blank` (na web, ao criar secret) | Campo **Path** não preenchido | Digite um nome, ex.: `desenvolvimento` |
| Comandos não fazem nada / tudo dá erro de conexão | Vault ainda **selado** após reiniciar o container | Rode `vault status`; se `Sealed: true`, destrave com 3 chaves (seção 3.2) ou ative o auto-unseal (seção 3.4) |
| `export: The term 'export' is not recognized...` | Comando de Bash digitado no PowerShell | Use `$env:VAULT_TOKEN = "valor"` (seção 9) |

### 11. Parar, reiniciar e limpar

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

### 12. Boas práticas de segurança

- Não use o `Initial Root Token` (nem a política `root`) em aplicações — use AppRole (seção 6.3) ou um token com política restrita (seção 6.2).
- Nunca salve Unseal Keys, Root Token, `role_id`/`secret_id` ou senhas em arquivos dentro de pastas versionadas no Git.
- Se algum desses valores foi colado em um chat, e-mail ou qualquer lugar fora do seu controle, considere-o exposto — gere novos (reinicialize o Vault ou rotacione o `secret_id`/token).
- Crie uma política por aplicação, liberando **só** os caminhos que ela realmente usa.
- Use HTTPS/TLS antes de deixar o Vault acessível por outra máquina (esta configuração usa `tls_disable = true`, só para localhost).
- Faça backup protegido do volume `/vault/data`.
- Teste sempre primeiro com senhas descartáveis, nunca com credenciais reais de produção.
- **Sobre o auto-unseal da seção 3.4:** ele guarda as 3 Unseal Keys em texto puro no arquivo `.env` local. Isso reduz a proteção que o esquema Shamir (3 de 5 chaves, guardadas separadamente) foi desenhado para dar — quem tiver acesso a esse `.env` já destrava o Vault sozinho. Para um ambiente que não seja só o seu laboratório local, prefira o **Auto Unseal nativo** do Vault com um serviço de nuvem (ex.: Azure Key Vault, AWS KMS), que elimina as Shamir Keys por completo em vez de só automatizar o envio delas.
