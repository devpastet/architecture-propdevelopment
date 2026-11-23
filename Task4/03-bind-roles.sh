#!/usr/bin/env bash
# Связывание групп пользователей с ролями и проверка прав.
set -euo pipefail

cat <<'YAML' | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata: {name: propdev-viewers}
roleRef: {apiGroup: rbac.authorization.k8s.io, kind: ClusterRole, name: cluster-viewer}
subjects:
  - {apiGroup: rbac.authorization.k8s.io, kind: Group, name: "propdev:viewers"}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata: {name: propdev-platform-engineers}
roleRef: {apiGroup: rbac.authorization.k8s.io, kind: ClusterRole, name: cluster-configurator}
subjects:
  - {apiGroup: rbac.authorization.k8s.io, kind: Group, name: "propdev:platform-engineers"}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata: {name: propdev-security}
roleRef: {apiGroup: rbac.authorization.k8s.io, kind: ClusterRole, name: security-admin}
subjects:
  - {apiGroup: rbac.authorization.k8s.io, kind: Group, name: "propdev:security"}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata: {name: propdev-cluster-admins}
roleRef: {apiGroup: rbac.authorization.k8s.io, kind: ClusterRole, name: cluster-admin}
subjects:
  - {apiGroup: rbac.authorization.k8s.io, kind: Group, name: "propdev:cluster-admins"}
YAML

# Доменные роли: RoleBinding ограничивает ClusterRole одним namespace
for ns in sales housing finance data; do
  cat <<YAML | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: {name: ${ns}-devops, namespace: ${ns}}
roleRef: {apiGroup: rbac.authorization.k8s.io, kind: ClusterRole, name: domain-devops}
subjects:
  - {apiGroup: rbac.authorization.k8s.io, kind: Group, name: "propdev:${ns}-devops"}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: {name: ${ns}-developers, namespace: ${ns}}
roleRef: {apiGroup: rbac.authorization.k8s.io, kind: ClusterRole, name: domain-developer}
subjects:
  - {apiGroup: rbac.authorization.k8s.io, kind: Group, name: "propdev:${ns}-developers"}
YAML
done

# Проверка: ожидаемый результат указан в комментарии
check() {  # user group verb resource namespace expected
  local args=(--as="$1" --as-group="$2" "$3" "$4")
  [[ "$5" == "-A" ]] && args+=(--all-namespaces) || args+=(-n "$5")
  local got; got="$(kubectl auth can-i "${args[@]}" 2>/dev/null || true)"
  printf '%-22s %-8s %-12s %-8s -> %-3s (ожидалось %s) %s\n' "$1" "$3" "$4" "$5" "$got" "$6" \
    "$([[ "$got" == "$6" ]] && echo OK || echo FAIL)"
}
echo; echo "Проверка прав:"
check ivan-viewer          propdev:viewers            list   pods        -A      yes
check ivan-viewer          propdev:viewers            list   secrets     -A      no
check ivan-viewer          propdev:viewers            create deployments sales   no
check petr-platform        propdev:platform-engineers create deployments finance yes
check petr-platform        propdev:platform-engineers create namespaces  -A      yes
check petr-platform        propdev:platform-engineers get    secrets     sales   no
check petr-platform        propdev:platform-engineers create rolebindings sales  no
check olga-security        propdev:security           get    secrets     -A      yes
check olga-security        propdev:security           create clusterrolebindings -A yes
check olga-security        propdev:security           delete deployments sales   no
check anna-sales-dev       propdev:sales-developers   list   pods        sales   yes
check anna-sales-dev       propdev:sales-developers   get    secrets     sales   no
check anna-sales-dev       propdev:sales-developers   list   pods        finance no
check maxim-housing-devops propdev:housing-devops     get    secrets     housing yes
check maxim-housing-devops propdev:housing-devops     get    secrets     sales   no
check maxim-housing-devops propdev:housing-devops     create rolebindings housing no
