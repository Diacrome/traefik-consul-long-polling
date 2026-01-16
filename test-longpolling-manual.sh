#!/bin/bash

echo "🚀 Manual Long Polling Test - Extended"
echo ""

docker-compose down -v
docker-compose build app
docker-compose up -d

echo "⏳ Waiting 30s..."
sleep 30

LINES_BEFORE_MONITOR=$(docker-compose logs monitor | wc -l)
LINES_BEFORE_TRAEFIK=$(docker-compose logs traefik | wc -l)

echo ""
echo "✅ Service:"
curl -s http://localhost/api | jq -c

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
KILL_TIME=$(date -u +"%H:%M:%S")
echo "💀 KILL APP at $KILL_TIME"
docker kill -s SIGKILL app

echo ""
echo "⏳ Wait 5s..."
sleep 5

DEREG_TIME=$(date -u +"%H:%M:%S")
echo ""
echo "🔧 DEREGISTER at $DEREG_TIME"
curl -s -X PUT http://localhost:8500/v1/agent/service/deregister/api-instance

echo ""
echo ""
echo "⏳ Waiting 10 seconds for Traefik to update..."
for i in {1..10}; do
    echo -ne "   ${i}/10s\r"
    sleep 1
done

echo ""
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 MONITOR EVENTS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
docker-compose logs monitor | tail -n +$((LINES_BEFORE_MONITOR + 1))

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📡 TRAEFIK CONFIGURATION CHANGES:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
docker-compose logs traefik | tail -n +$((LINES_BEFORE_TRAEFIK + 1)) | grep -i "Configuration received" || echo "No configuration changes detected"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎯 EXTRACTED EVENTS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

NEW_MONITOR_LOGS=$(docker-compose logs monitor | tail -n +$((LINES_BEFORE_MONITOR + 1)))
NEW_TRAEFIK_LOGS=$(docker-compose logs traefik | tail -n +$((LINES_BEFORE_TRAEFIK + 1)))

HC=$(echo "$NEW_MONITOR_LOGS" | grep "HEALTH CHECK FAILED" | head -1)
CD=$(echo "$NEW_MONITOR_LOGS" | grep "CONSUL DEREGISTERED" | head -1)
TR=$(echo "$NEW_MONITOR_LOGS" | grep "TRAEFIK REMOVED" | head -1)
DELAY=$(echo "$NEW_MONITOR_LOGS" | grep "LONG POLLING DELAY" | head -1)

# Извлекаем конфигурации Traefik
TRAEFIK_CONFIGS=$(echo "$NEW_TRAEFIK_LOGS" | grep "Configuration received" | grep "consulcatalog")

echo ""
echo "From Monitor:"
[ -n "$HC" ] && echo "  ✅ $HC" || echo "  ⚠️  Health Check - not detected"
[ -n "$CD" ] && echo "  ✅ $CD" || echo "  ❌ Consul Deregister - NOT DETECTED"
[ -n "$TR" ] && echo "  ✅ $TR" || echo "  ❌ Traefik Remove - NOT DETECTED"

echo ""
echo "From Traefik:"
if [ -n "$TRAEFIK_CONFIGS" ]; then
    echo "$TRAEFIK_CONFIGS" | while IFS= read -r line; do
        # Извлекаем timestamp (между time=" и ")
        TIMESTAMP=$(echo "$line" | sed -n 's/.*time="\([^"]*\)".*/\1/p')
        # Проверяем пустая ли конфигурация
        if echo "$line" | grep -q '"http":{}'; then
            echo "  ✅ [$TIMESTAMP] Traefik received EMPTY config (service removed)"
        else
            echo "  📝 [$TIMESTAMP] Traefik received config update"
        fi
    done
else
    echo "  ❌ No Traefik configuration changes detected"
fi

echo ""
if [ -n "$DELAY" ]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "⚡ $DELAY"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "🎉 SUCCESS! Long polling works!"
else
    echo "⚠️  Delay not calculated (Traefik event missing)"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 TIMING SUMMARY:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "$NEW_MONITOR_LOGS" | grep -A 15 "TIMING SUMMARY" || echo "Not generated yet"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📈 DETAILED TIMELINE:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Kill time:              $KILL_TIME"

# Извлекаем времена из логов (между [ и ])
HC_TIME=$(echo "$HC" | sed -n 's/.*\[\([^]]*\)\].*/\1/p')
CD_TIME=$(echo "$CD" | sed -n 's/.*\[\([^]]*\)\].*/\1/p')

# Первое изменение конфигурации Traefik после kill
FIRST_TRAEFIK_CHANGE=$(echo "$TRAEFIK_CONFIGS" | head -1 | sed -n 's/.*time="\([^"]*\)".*/\1/p')

echo "Health check failed:    ${HC_TIME:-N/A}"
echo "Traefik notified:       ${FIRST_TRAEFIK_CHANGE:-N/A}"
echo "Consul deregistered:    ${CD_TIME:-N/A}"

# Вычисляем задержку между Traefik и Consul
if [ -n "$FIRST_TRAEFIK_CHANGE" ] && [ -n "$CD_TIME" ]; then
    echo ""
    echo "⚡ Analysis:"
    echo "   Traefik was notified at: $FIRST_TRAEFIK_CHANGE"
    echo "   Consul deregistered at:  $CD_TIME"
    echo "   → Traefik received update via long polling!"
fi

echo ""
echo "✅ Final verification:"
echo "   Consul services: $(curl -s http://localhost:8500/v1/catalog/service/api | jq 'length')"
echo "   HTTP test: $(curl -s -o /dev/null -w '%{http_code}' http://localhost/api)"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 All Traefik configuration changes (last 5):"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
docker-compose logs traefik | grep "Configuration received" | grep "consulcatalog" | tail -5 | while IFS= read -r line; do
    TIMESTAMP=$(echo "$line" | sed -n 's/.*time="\([^"]*\)".*/\1/p')
    if echo "$line" | grep -q '"http":{}'; then
        echo "[$TIMESTAMP] ✅ EMPTY config (service removed)"
    else
        echo "[$TIMESTAMP] 📝 Config with services"
    fi
done

echo ""
echo "🧹 docker-compose down"
