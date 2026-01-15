#!/bin/bash

echo "🚀 Manual Long Polling Test - Extended"
echo ""

docker-compose down -v
docker-compose build app
docker-compose up -d

echo "⏳ Waiting 30s..."
sleep 30

LINES_BEFORE=$(docker-compose logs monitor | wc -l)

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
echo "📊 ALL EVENTS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
docker-compose logs monitor | tail -n +$((LINES_BEFORE + 1))

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎯 EXTRACTED EVENTS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

NEW_LOGS=$(docker-compose logs monitor | tail -n +$((LINES_BEFORE + 1)))

HC=$(echo "$NEW_LOGS" | grep "HEALTH CHECK FAILED" | head -1)
CD=$(echo "$NEW_LOGS" | grep "CONSUL DEREGISTERED" | head -1)
TR=$(echo "$NEW_LOGS" | grep "TRAEFIK REMOVED" | head -1)
DELAY=$(echo "$NEW_LOGS" | grep "LONG POLLING DELAY" | head -1)

echo ""
[ -n "$HC" ] && echo "✅ $HC" || echo "⚠️  Health Check - not detected"
[ -n "$CD" ] && echo "✅ $CD" || echo "❌ Consul Deregister - NOT DETECTED"
[ -n "$TR" ] && echo "✅ $TR" || echo "❌ Traefik Remove - NOT DETECTED"

echo ""
if [ -n "$DELAY" ]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "⚡ $DELAY"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "🎉 SUCCESS! Long polling works!"
else
    echo "⚠️  Delay not calculated (Traefik event missing)"
    echo ""
    echo "Checking Traefik manually:"
    TRAEFIK_SERVICES=$(curl -s http://localhost:8080/api/http/services 2>/dev/null | jq -r '.[].name' | grep -c api || echo "0")
    echo "   Traefik services with 'api': $TRAEFIK_SERVICES (should be 0)"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 TIMING SUMMARY:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "$NEW_LOGS" | grep -A 15 "TIMING SUMMARY" || echo "Not generated yet"

echo ""
echo "✅ Final verification:"
echo "   Consul services: $(curl -s http://localhost:8500/v1/catalog/service/api | jq 'length')"
echo "   HTTP test: $(curl -s -o /dev/null -w '%{http_code}' http://localhost/api)"

echo ""
echo "🧹 docker-compose down"
