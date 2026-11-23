#!/usr/bin/env bash
# Развёртывание четырёх сервисов, применение сетевых политик и проверка трафика.
# Нужен CNI с поддержкой NetworkPolicy: minikube start --cni=calico
set -euo pipefail
cd "$(dirname "$0")"

for role in front-end back-end-api admin-front-end admin-back-end-api; do
  kubectl get pod "${role}-app" >/dev/null 2>&1 || \
    kubectl run "${role}-app" --image=nginx --labels role="${role}" --expose --port 80
done
kubectl wait --for=condition=Ready pod -l 'role in (front-end,back-end-api,admin-front-end,admin-back-end-api)' --timeout=180s

kubectl apply -f non-admin-api-allow.yaml
sleep 5

# probe <роль клиента> <сервис> <ожидание: ok|blocked>
probe() {
  local name="test-$RANDOM"
  local res
  if kubectl run "$name" --rm -i --restart=Never --image=alpine --labels role="$1" -- \
       wget -qO- --timeout=2 "http://$2" >/dev/null 2>&1; then res=ok; else res=blocked; fi
  printf '%-20s -> %-24s %-8s (ожидалось %s) %s\n' "$1" "$2" "$res" "$3" "$([[ $res == "$3" ]] && echo OK || echo FAIL)"
}

echo "Проверка трафика:"
probe front-end          back-end-api-app        ok
probe back-end-api       front-end-app           ok
probe admin-front-end    admin-back-end-api-app  ok
probe admin-back-end-api admin-front-end-app     ok
probe front-end          admin-back-end-api-app  blocked
probe admin-front-end    back-end-api-app        blocked
probe back-end-api       admin-back-end-api-app  blocked
probe none               back-end-api-app        blocked
probe none               admin-back-end-api-app  blocked
