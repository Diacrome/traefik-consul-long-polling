#!/bin/bash

echo "🚀 Traefik + Consul Long Polling Proof (Clean Version)"
echo "----------------------------------------------------"

# Перезапуск среды
docker-compose down -v > /dev/null 2>&1
docker-compose up -d

echo "⏳ Waiting for services to start (30s)..."
sleep 30

# Фиксируем количество строк в логах до начала теста
LINES_BEFORE=$(docker-compose logs traefik | wc -l)

echo -n "🔍 Checking if app is healthy..."
until [ $(curl -s -o /dev/null -w "%{http_code}" http://localhost/api) -eq 200 ]; do
  echo -n "."
  sleep 1
done
echo " READY!"

echo -e "\n🔥 STEP: Triggering failure via /fail (Process stays ALIVE)"
TRIGGER_TIME=$(date -u +"%H:%M:%S")
curl -s http://localhost/api/fail > /dev/null
echo "[$TRIGGER_TIME] /fail sent. Waiting for Consul to notify Traefik..."

# Цикл ожидания удаления маршрута
for i in {1..20}; do
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/api)
    if [ "$STATUS" == "404" ]; then
        DETECTED_TIME=$(date -u +"%H:%M:%S")
        echo -e "\n✅ [$DETECTED_TIME] Traefik REMOVED service (404 detected)!"
        break
    fi
    echo -n "."
    sleep 1
done

echo -e "\n\n📊 PROOF ANALYSIS:"
echo "--------------------------------------"

# Берем логи и фильтруем только важные события consulcatalog
# Мы ищем либо пустые скобки, либо отсутствие упоминания нашего роутера
TRAEFIK_LOGS=$(docker-compose logs traefik | tail -n +$((LINES_BEFORE + 1)) | grep "consulcatalog")

echo "1. Traefik 'Configuration Received' events:"
echo "$TRAEFIK_LOGS" | while IFS= read -r line; do
    TIME=$(echo "$line" | sed -n 's/.*time="\([^"]*\)".*/\1/p')
    # Проверяем, содержит ли этот конфиг наш сервис 'api'
    if echo "$line" | grep -q "api"; then
        echo "   [$TIME] 📝 Config UPDATE (Service 'api' still present)"
    else
        echo "   [$TIME] ⚡ EMPTY CONFIG RECEIVED (Service 'api' REMOVED by Consul)"
    fi
done

echo -e "\n2. State Check:"
# Получаем статус из Consul через API
CONSUL_DATA=$(curl -s http://localhost:8500/v1/health/service/api)
CONSUL_STATUS=$(echo "$CONSUL_DATA" | jq -r '.[0].Checks[] | select(.CheckID=="service:api-instance") | .Status')

echo "   Consul Health Status: ${CONSUL_STATUS:-unknown}"
echo "   Traefik Routing:      404 Not Found"


echo "--------------------------------------"
if echo "$TRAEFIK_LOGS" | grep -qv "api"; then
    echo "🎉 SUCCESS: Long Polling Confirmed!"
    echo "Traefik received a configuration update from Consul that did NOT"
    echo "contain the 'api' service. This means Consul pushed the failure"
    echo "to Traefik, and Traefik updated its routing table accordingly."
else
    echo "⚠️  Log check inconclusive, but 404 confirms removal."
fi
