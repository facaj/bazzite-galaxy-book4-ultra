#!/usr/bin/bash
# Gera o par de chaves usado para assinar ov02c10 e MAX98390 (Secure Boot).
#
# Saída em certs/ (ignorado pelo git):
#   galaxybook-mok.priv  chave privada   -> NUNCA publique; vai no secret MOK_PRIVATE_KEY
#   galaxybook-mok.der   certificado     -> vai no secret MOK_PUBLIC_CERT (base64)
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p certs

if [[ -e certs/galaxybook-mok.priv ]]; then
    echo "certs/galaxybook-mok.priv já existe; apague-o antes para gerar outro." >&2
    exit 1
fi

openssl req -new -x509 -newkey rsa:2048 -nodes -sha256 -days 36500 \
    -subj "/CN=Galaxy Book4 Ultra Bazzite kmod signing key/" \
    -addext "extendedKeyUsage=codeSigning" \
    -keyout certs/galaxybook-mok.priv \
    -outform DER -out certs/galaxybook-mok.der
chmod 600 certs/galaxybook-mok.priv

cat <<MSG
Chaves geradas em certs/.

Para o build no GitHub Actions, crie estes secrets no repositório
(Settings > Secrets and variables > Actions):

  MOK_PRIVATE_KEY   conteúdo de: cat certs/galaxybook-mok.priv
  MOK_PUBLIC_CERT   conteúdo de: base64 -w0 certs/galaxybook-mok.der

Guarde uma cópia segura da chave privada: se ela mudar, será preciso inscrever
a nova chave no MOK outra vez (ujust galaxybook-enroll-key).
MSG
