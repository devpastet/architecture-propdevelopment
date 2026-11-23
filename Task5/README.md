# Задание 5. Управление трафиком внутри кластера

`non-admin-api-allow.yaml` содержит пять сетевых политик:

| Политика | Назначение |
|---|---|
| `default-deny-ingress` | Запрещает весь входящий трафик ко всем подам namespace (изоляция по умолчанию) |
| `back-end-api-allow-from-front-end` | front-end → back-end-api |
| `front-end-allow-from-back-end-api` | back-end-api → front-end |
| `admin-back-end-api-allow-from-admin-front-end` | admin-front-end → admin-back-end-api |
| `admin-front-end-allow-from-admin-back-end-api` | admin-back-end-api → admin-front-end |

Ответный трафик в рамках установленного соединения разрешается автоматически (политики работают с учётом состояния соединений). Отдельные правила для обратного направления нужны, чтобы каждая сторона пары могла сама начинать соединение. Новый сервис, добавленный в namespace, по умолчанию изолирован политикой `default-deny-ingress`.

## Запуск

```bash
minikube start --cni=calico          # NetworkPolicy работает только с поддерживающим её CNI
kubectl run front-end-app          --image=nginx --labels role=front-end          --expose --port 80
kubectl run back-end-api-app       --image=nginx --labels role=back-end-api       --expose --port 80
kubectl run admin-front-end-app    --image=nginx --labels role=admin-front-end    --expose --port 80
kubectl run admin-back-end-api-app --image=nginx --labels role=admin-back-end-api --expose --port 80
kubectl apply -f non-admin-api-allow.yaml
```

## Проверка

Тестовый под должен получить метку той роли, от имени которой проверяется доступ:

```bash
kubectl run test-$RANDOM --rm -i -t --image=alpine --labels role=front-end -- sh
/ # wget -qO- --timeout=2 http://back-end-api-app         # ответ nginx
/ # wget -qO- --timeout=2 http://admin-back-end-api-app   # wget: download timed out
```

Автоматическая проверка всех комбинаций: `./deploy-and-test.sh`.
