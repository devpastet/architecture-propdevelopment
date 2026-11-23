#!/usr/bin/env bash
# Создание namespace доменов и ролей кластера.
set -euo pipefail

# Namespace по доменам оргструктуры PropDevelopment
for ns in sales housing finance data; do
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
  kubectl label namespace "$ns" propdev/domain="$ns" --overwrite
done

cat <<'YAML' | kubectl apply -f -
# 1. Просмотр ресурсов кластера без секретов
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: cluster-viewer
  labels: {propdev/rbac: "true"}
rules:
  - apiGroups: [""]
    resources: [pods, services, endpoints, configmaps, events, namespaces, nodes,
                persistentvolumes, persistentvolumeclaims, replicationcontrollers,
                serviceaccounts, resourcequotas, limitranges]
    verbs: [get, list, watch]
  - apiGroups: [apps]
    resources: [deployments, replicasets, statefulsets, daemonsets]
    verbs: [get, list, watch]
  - apiGroups: [batch]
    resources: [jobs, cronjobs]
    verbs: [get, list, watch]
  - apiGroups: [networking.k8s.io]
    resources: [ingresses, networkpolicies]
    verbs: [get, list, watch]
  - apiGroups: [autoscaling]
    resources: [horizontalpodautoscalers]
    verbs: [get, list, watch]
  - apiGroups: [storage.k8s.io]
    resources: [storageclasses]
    verbs: [get, list, watch]
---
# 2. Настройка кластера: всё, кроме чтения секретов и RBAC
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: cluster-configurator
  labels: {propdev/rbac: "true"}
rules:
  - apiGroups: [""]
    resources: [namespaces, pods, services, endpoints, configmaps,
                persistentvolumes, persistentvolumeclaims, resourcequotas,
                limitranges, serviceaccounts, replicationcontrollers]
    verbs: [get, list, watch, create, update, patch, delete]
  - apiGroups: [""]
    resources: [events, pods/log]
    verbs: [get, list, watch]
  - apiGroups: [""]
    resources: [nodes]
    verbs: [get, list, watch, patch]          # cordon / uncordon
  - apiGroups: [""]
    resources: [pods/eviction]
    verbs: [create]                           # drain
  - apiGroups: [""]
    resources: [secrets]
    verbs: [create, update, patch]            # записать секрет можно, прочитать — нет
  - apiGroups: [apps]
    resources: [deployments, replicasets, statefulsets, daemonsets, deployments/scale]
    verbs: [get, list, watch, create, update, patch, delete]
  - apiGroups: [batch]
    resources: [jobs, cronjobs]
    verbs: [get, list, watch, create, update, patch, delete]
  - apiGroups: [networking.k8s.io]
    resources: [ingresses, ingressclasses, networkpolicies]
    verbs: [get, list, watch, create, update, patch, delete]
  - apiGroups: [autoscaling]
    resources: [horizontalpodautoscalers]
    verbs: [get, list, watch, create, update, patch, delete]
  - apiGroups: [storage.k8s.io]
    resources: [storageclasses]
    verbs: [get, list, watch, create, update, patch, delete]
  - apiGroups: [apiextensions.k8s.io]
    resources: [customresourcedefinitions]
    verbs: [get, list, watch, create, update, patch, delete]
---
# 3. Привилегированная роль ИБ: секреты и RBAC, без изменения нагрузки
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: security-admin
  labels: {propdev/rbac: "true"}
rules:
  - apiGroups: ["*"]
    resources: ["*"]
    verbs: [get, list, watch]                 # включая secrets
  - apiGroups: [rbac.authorization.k8s.io]
    resources: [roles, rolebindings, clusterroles, clusterrolebindings]
    verbs: [get, list, watch, create, update, patch, delete, bind, escalate]
  - apiGroups: [networking.k8s.io]
    resources: [networkpolicies]
    verbs: [create, update, patch, delete]
  - apiGroups: [""]
    resources: [serviceaccounts]
    verbs: [create, update, patch, delete]
  - apiGroups: [certificates.k8s.io]
    resources: [certificatesigningrequests, certificatesigningrequests/approval]
    verbs: [get, list, watch, update]
  - apiGroups: [certificates.k8s.io]
    resources: [signers]
    resourceNames: [kubernetes.io/kube-apiserver-client]
    verbs: [approve]
  - apiGroups: [""]
    resources: [users, groups, serviceaccounts]
    verbs: [impersonate]
---
# 4. DevOps домена: полный доступ к своему namespace, включая секреты
#    (выдаётся через RoleBinding, поэтому действует только в одном namespace)
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: domain-devops
  labels: {propdev/rbac: "true"}
rules:
  - apiGroups: [""]
    resources: [pods, services, endpoints, configmaps, secrets, serviceaccounts,
                persistentvolumeclaims, replicationcontrollers]
    verbs: [get, list, watch, create, update, patch, delete]
  - apiGroups: [""]
    resources: [pods/log, events]
    verbs: [get, list, watch]
  - apiGroups: [""]
    resources: [pods/exec, pods/portforward]
    verbs: [create, get]
  - apiGroups: [apps]
    resources: [deployments, replicasets, statefulsets, daemonsets, deployments/scale]
    verbs: [get, list, watch, create, update, patch, delete]
  - apiGroups: [batch]
    resources: [jobs, cronjobs]
    verbs: [get, list, watch, create, update, patch, delete]
  - apiGroups: [networking.k8s.io]
    resources: [ingresses, networkpolicies]
    verbs: [get, list, watch, create, update, patch, delete]
  - apiGroups: [autoscaling]
    resources: [horizontalpodautoscalers]
    verbs: [get, list, watch, create, update, patch, delete]
  - apiGroups: [rbac.authorization.k8s.io]
    resources: [roles, rolebindings]
    verbs: [get, list, watch]
---
# 5. Разработчик домена: просмотр, логи, выкатка; без секретов и exec
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: domain-developer
  labels: {propdev/rbac: "true"}
rules:
  - apiGroups: [""]
    resources: [pods, services, endpoints, configmaps, events, persistentvolumeclaims]
    verbs: [get, list, watch]
  - apiGroups: [""]
    resources: [pods/log]
    verbs: [get, list]
  - apiGroups: [""]
    resources: [pods]
    verbs: [delete]                           # перезапуск pod
  - apiGroups: [""]
    resources: [pods/portforward]
    verbs: [create, get]
  - apiGroups: [""]
    resources: [configmaps]
    verbs: [create, update, patch]
  - apiGroups: [apps]
    resources: [deployments, replicasets, statefulsets]
    verbs: [get, list, watch, update, patch]
  - apiGroups: [batch]
    resources: [jobs, cronjobs]
    verbs: [get, list, watch, create, delete]
  - apiGroups: [networking.k8s.io]
    resources: [ingresses]
    verbs: [get, list, watch]
YAML

kubectl get clusterroles -l propdev/rbac=true
