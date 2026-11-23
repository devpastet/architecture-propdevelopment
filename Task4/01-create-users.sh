#!/usr/bin/env bash
# Создание пользователей Kubernetes по клиентским сертификатам.
# CN сертификата — имя пользователя, O — группа (по группам выдаются роли).
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-minikube}"
CERT_DIR="${CERT_DIR:-$(dirname "$0")/users}"
EXPIRATION_SECONDS="${EXPIRATION_SECONDS:-31536000}"   # 1 год

# пользователь:группа
USERS=(
  "ivan-viewer:propdev:viewers"
  "petr-platform:propdev:platform-engineers"
  "olga-security:propdev:security"
  "anna-sales-dev:propdev:sales-developers"
  "maxim-housing-devops:propdev:housing-devops"
)

mkdir -p "$CERT_DIR"
chmod 700 "$CERT_DIR"

for entry in "${USERS[@]}"; do
  user="${entry%%:*}"
  group="${entry#*:}"
  echo "==> Пользователь ${user} (группа ${group})"

  # 1. Закрытый ключ и запрос на сертификат
  openssl genrsa -out "${CERT_DIR}/${user}.key" 2048 2>/dev/null
  chmod 600 "${CERT_DIR}/${user}.key"
  openssl req -new -key "${CERT_DIR}/${user}.key" \
    -out "${CERT_DIR}/${user}.csr" -subj "/CN=${user}/O=${group}"

  # 2. CertificateSigningRequest в Kubernetes
  kubectl delete csr "${user}" --ignore-not-found >/dev/null
  cat <<YAML | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: ${user}
spec:
  request: $(base64 < "${CERT_DIR}/${user}.csr" | tr -d '\n')
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: ${EXPIRATION_SECONDS}
  usages:
    - client auth
YAML

  # 3. Одобрение и получение сертификата
  kubectl certificate approve "${user}"
  for _ in $(seq 1 20); do
    cert="$(kubectl get csr "${user}" -o jsonpath='{.status.certificate}')"
    [[ -n "$cert" ]] && break
    sleep 1
  done
  echo "$cert" | base64 --decode > "${CERT_DIR}/${user}.crt"

  # 4. Пользователь и контекст в kubeconfig
  kubectl config set-credentials "${user}" \
    --client-certificate="${CERT_DIR}/${user}.crt" \
    --client-key="${CERT_DIR}/${user}.key" --embed-certs=true
  kubectl config set-context "${user}" --cluster="${CLUSTER_NAME}" --user="${user}"
done

echo "Готово. Контексты: $(kubectl config get-contexts -o name | tr '\n' ' ')"
