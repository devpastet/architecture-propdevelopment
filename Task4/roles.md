# Ролевая модель доступа к Kubernetes PropDevelopment

## Принципы

- **Наименьшие привилегии.** По умолчанию доступа нет. Права выдаются только группам, не отдельным пользователям.
- **Разграничение по оргструктуре.** Каждому домену компании соответствует свой namespace: `sales` (продажи), `housing` (ЖКУ, включая новый smart-home-service), `finance` (финансы), `data` (дата). Права продуктовых команд действуют только в namespace своего домена.
- **Секреты — привилегированное действие.** Читать `secrets` могут только DevOps-инженеры своего домена (в своём namespace), специалист по ИБ и аварийные администраторы.
- **Пользователи** аутентифицируются по клиентским X.509-сертификатам, подписанным CA кластера: `CN` — имя пользователя, `O` — группа. В продуктиве вместо сертификатов используется OIDC (Keycloak из Task3), группы приходят в claim `groups`.

## Таблица ролей

| Роль | Права роли | Группы пользователей |
|---|---|---|
| `cluster-viewer` (ClusterRole + ClusterRoleBinding) | Только просмотр (`get`, `list`, `watch`) ресурсов во всех namespace: pods, deployments, services, configmaps, ingress, events, nodes, namespaces, networkpolicies, PV/PVC, jobs. **Нет доступа к secrets**, `pods/exec`, `pods/log`, RBAC. Изменений нет. | `propdev:viewers` — менеджеры операционных команд, владельцы продуктов, бизнес-аналитики, внешние аудиторы |
| `cluster-configurator` (ClusterRole + ClusterRoleBinding) | Настройка кластера: создание и изменение namespaces, workloads (deployments, statefulsets, daemonsets, jobs), services, ingress, configmaps, networkpolicies, resourcequotas, limitranges, PV/PVC, storageclasses, HPA, CRD; `cordon/drain` узлов (patch nodes); просмотр логов. **Нет чтения secrets** (только создание и обновление, без `get/list`) и **нет управления RBAC**. | `propdev:platform-engineers` — платформенная (инфраструктурная) команда |
| `security-admin` (ClusterRole + ClusterRoleBinding) | Привилегированная роль: чтение всех ресурсов, **просмотр secrets** во всех namespace, управление RBAC (roles, rolebindings, clusterroles, clusterrolebindings), networkpolicies, serviceaccounts, просмотр и одобрение CSR; `impersonate` для проверки прав. Изменение workloads запрещено. | `propdev:security` — специалист по информационной безопасности |
| `cluster-admin` (встроенная ClusterRole + ClusterRoleBinding) | Полный доступ ко всему кластеру. Используется только как аварийный доступ (break-glass): выдаётся по заявке, сессии журналируются (audit log). | `propdev:cluster-admins` — руководитель платформенной команды, дежурный администратор |
| `domain-devops` (ClusterRole + RoleBinding в namespace домена) | Полное управление ресурсами **своего namespace**: workloads, services, ingress, configmaps, **secrets (просмотр и изменение)**, serviceaccounts, networkpolicies, HPA, PVC, `pods/exec`, `pods/log`, `port-forward`. Не может менять RBAC, квоты и сам namespace. Нет доступа к чужим namespace. | `propdev:sales-devops`, `propdev:housing-devops`, `propdev:finance-devops`, `propdev:data-devops` — DevOps-инженеры и инженеры по эксплуатации доменов |
| `domain-developer` (ClusterRole + RoleBinding в namespace домена) | В **своём namespace**: просмотр ресурсов, логи, перезапуск (удаление pods), обновление deployments и configmaps (выкатка), `port-forward`. **Без secrets**, без `exec`, без RBAC, без networkpolicies. | `propdev:sales-developers`, `propdev:housing-developers`, `propdev:finance-developers`, `propdev:data-developers` — разработчики продуктовых команд |

## Пользователи, созданные скриптами

| Пользователь (CN) | Группа (O) | Итоговая роль |
|---|---|---|
| `ivan-viewer` | `propdev:viewers` | cluster-viewer |
| `petr-platform` | `propdev:platform-engineers` | cluster-configurator |
| `olga-security` | `propdev:security` | security-admin |
| `anna-sales-dev` | `propdev:sales-developers` | domain-developer в `sales` |
| `maxim-housing-devops` | `propdev:housing-devops` | domain-devops в `housing` |

## Скрипты

Скрипты запускаются по порядку на чистом Minikube (`minikube start`):

1. `01-create-users.sh` — создаёт ключи и CSR пользователей, подписывает их через Kubernetes CSR API, добавляет пользователей и контексты в kubeconfig.
2. `02-create-roles.sh` — создаёт namespace доменов и ClusterRole из таблицы.
3. `03-bind-roles.sh` — связывает группы с ролями (ClusterRoleBinding и RoleBinding) и проверяет права через `kubectl auth can-i`.

Проверка вручную:

```bash
kubectl --context=ivan-viewer get pods -A              # разрешено
kubectl --context=ivan-viewer get secrets -A           # Forbidden
kubectl --context=anna-sales-dev -n sales get pods     # разрешено
kubectl --context=anna-sales-dev -n finance get pods   # Forbidden
kubectl --context=olga-security get secrets -A         # разрешено
```
