FROM hashicorp/vault:1.18

COPY vault.hcl /vault/config/vault.hcl

EXPOSE 8200

ENTRYPOINT ["vault"]
CMD ["server", "-config=/vault/config/vault.hcl"]
