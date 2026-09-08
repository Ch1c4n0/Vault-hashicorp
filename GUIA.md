# HashiCorp Vault local com Docker

Este guia mostra como guardar senhas no HashiCorp Vault usando Docker, linha de comando e navegador.

> **Importante:** esta configuração foi feita para laboratório local. Ela usa HTTP sem TLS. Não publique a porta `8200` na internet e não use esta configuração diretamente em produção.

## 1. Antes de começar

Você precisa ter:

- Docker Desktop aberto e funcionando.
- PowerShell ou outro terminal.
- Acesso à pasta `Vault` deste projeto.

Neste guia, os comandos começam com `PS>`. Digite somente o que vem depois desse marcador.

## 2. Iniciar o Vault

Abra o terminal dentro desta pasta e execute:

```powershell
docker compose up -d --build
```

Confira se o container está funcionando:

```powershell
docker compose ps
docker compose logs vault
```

Abra no navegador:

```text
http://localhost:8200
```

Você verá a tela de inicialização. Neste momento, o Vault ainda está **selado**. Isso é normal.

## 3. Inicializar o Vault pela linha de comando

### 3.1 Gerar as chaves iniciais

Execute uma única vez:

```powershell
docker compose exec vault vault operator init -key-shares=5 -key-threshold=3
```

O resultado terá cinco `Unseal Key` e um `Initial Root Token`.

### Pare aqui e guarde as informações

1. Copie o resultado para um gerenciador de senhas seguro.
2. Não salve esse resultado no Git, no OneDrive ou em um arquivo do projeto.
3. Você precisará de **três chaves diferentes** para destravar o Vault.
4. O `Initial Root Token` é uma credencial administrativa. Use-o apenas para a configuração inicial.

### 3.2 Destravar o Vault

Use três chaves diferentes, uma por vez:

```powershell
docker compose exec vault vault operator unseal
```

Quando aparecer `Unseal Key (will be hidden):`, cole a primeira chave e pressione Enter. Repita o comando com a segunda e a terceira chave.

Verifique o estado:

```powershell
docker compose exec vault vault status
```

O campo `Sealed` deve aparecer como `false`.

## 4. Criar um espaço para senhas

Defina o token administrativo apenas na sessão atual do PowerShell:

```powershell
$env:VAULT_TOKEN = "COLE_AQUI_O_INITIAL_ROOT_TOKEN"
```

Ative o mecanismo de segredos KV versão 2:

```powershell
docker compose exec -e VAULT_TOKEN=$env:VAULT_TOKEN vault vault secrets enable -path=secret kv-v2
```

Se aparecer que o caminho já está em uso, ele já foi criado. Nesse caso, pode continuar.

## 5. Gravar uma senha pela linha de comando

Exemplo: uma senha de um banco de desenvolvimento.

```powershell
docker compose exec -e VAULT_TOKEN=$env:VAULT_TOKEN vault vault kv put secret/desenvolvimento banco_usuario="app_user" banco_senha="Troque_Esta_Senha"
```

Leia o segredo:

```powershell
docker compose exec -e VAULT_TOKEN=$env:VAULT_TOKEN vault vault kv get secret/desenvolvimento
```

Leia somente um campo:

```powershell
docker compose exec -e VAULT_TOKEN=$env:VAULT_TOKEN vault vault kv get -field=banco_senha secret/desenvolvimento
```

Para atualizar a senha, execute o mesmo comando `kv put` com o novo valor. O Vault cria uma nova versão do segredo.

## 6. Usar a interface web

1. Abra `http://localhost:8200`.
2. Se a tela pedir o método de autenticação, escolha **Token**.
3. Cole o `Initial Root Token`.
4. Clique em **Sign In**.
5. Abra **Secrets Engines**.
6. Clique em `secret/`.
7. Clique em **Create secret**.
8. Em **Path**, digite `desenvolvimento`.
9. Crie os campos `banco_usuario` e `banco_senha`.
10. Clique em **Save**.

Para visualizar o valor depois:

1. Entre em **Secrets Engines**.
2. Abra `secret/`.
3. Abra `desenvolvimento`.
4. Clique em **Reveal values**.

O navegador pode esconder os valores de propósito. Isso ajuda a evitar que uma senha seja exposta por acidente.

## 7. Conferir o resultado pelos dois caminhos

O segredo criado na interface web deve aparecer no terminal:

```powershell
docker compose exec -e VAULT_TOKEN=$env:VAULT_TOKEN vault vault kv get secret/desenvolvimento
```

E o segredo criado no terminal deve aparecer no navegador em `secret/`.

## 8. Encerrar e iniciar novamente

Parar os containers sem apagar os dados:

```powershell
docker compose down
```

Iniciar novamente:

```powershell
docker compose up -d
```

Como os dados ficam no volume Docker `vault-data`, os segredos continuam existindo. Depois de reiniciar, o Vault poderá voltar selado; nesse caso, use três `vault operator unseal` novamente.

## 9. Comandos de diagnóstico

Ver os containers:

```powershell
docker compose ps
```

Ver os logs:

```powershell
docker compose logs -f vault
```

Ver os caminhos de segredos disponíveis:

```powershell
docker compose exec -e VAULT_TOKEN=$env:VAULT_TOKEN vault vault secrets list
```

## 10. Limpeza total do laboratório

> **Atenção:** este comando apaga os dados e os segredos deste Vault local.

```powershell
docker compose down -v
```

Depois da limpeza, será necessário repetir a inicialização e guardar novas chaves.

## 11. Boas práticas simples

- Não use o `Initial Root Token` em aplicações.
- Não envie tokens, chaves ou senhas para o Git.
- Crie tokens e políticas com permissões menores para cada aplicação.
- Use HTTPS/TLS antes de permitir acesso por outra máquina.
- Faça backup protegido do volume `/vault/data`.
- Teste primeiro com senhas descartáveis.
