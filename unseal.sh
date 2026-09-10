#!/bin/sh
# Fica vigiando o Vault para sempre: toda vez que ele estiver selado
# (por exemplo, apos "docker restart local-vault", reboot da maquina, etc.),
# destrava automaticamente com as 3 chaves em VAULT_UNSEAL_KEY_1/2/3.
set -eu

echo "[vault-unseal] monitorando $VAULT_ADDR (verifica a cada 5s)..."

while true; do
  set +e
  saida=$(vault status 2>&1)
  code=$?
  set -e

  if [ "$code" -eq 0 ] || [ "$code" -eq 2 ]; then
    if echo "$saida" | grep -qi "Sealed.*true"; then
      echo "[vault-unseal] Vault selado. Destravando com as 3 chaves..."
      vault operator unseal "$VAULT_UNSEAL_KEY_1" >/dev/null
      vault operator unseal "$VAULT_UNSEAL_KEY_2" >/dev/null
      vault operator unseal "$VAULT_UNSEAL_KEY_3" >/dev/null
      echo "[vault-unseal] Vault destravado com sucesso."
    fi
  fi

  sleep 5
done
