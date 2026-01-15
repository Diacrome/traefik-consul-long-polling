#!/usr/bin/env python3
import requests
import time
import threading
import sys
from datetime import datetime

sys.stdout = sys.stderr = open(sys.stdout.fileno(), 'w', buffering=1)

CONSUL_URL = "http://consul:8500"
TRAEFIK_URL = "http://traefik:8080"
SERVICE_NAME = "api"

events = {
    "consul_deregister_time": None,
    "traefik_update_time": None,
    "health_check_fail_time": None
}

service_was_registered = False

def get_timestamp():
    return datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"

def log(message):
    print(f"{message}", flush=True)

def wait_for_services():
    log("⏳ Waiting for Consul...")
    for i in range(30):
        try:
            requests.get(f"{CONSUL_URL}/v1/status/leader", timeout=2)
            log("✅ Consul is ready")
            break
        except:
            time.sleep(1)

    log("⏳ Waiting for Traefik...")
    for i in range(30):
        try:
            requests.get(f"{TRAEFIK_URL}/api/http/services", timeout=2)
            log("✅ Traefik is ready")
            break
        except:
            time.sleep(1)

    log(f"⏳ Waiting for service '{SERVICE_NAME}' to register...")
    for i in range(60):
        try:
            response = requests.get(f"{CONSUL_URL}/v1/catalog/service/{SERVICE_NAME}", timeout=2)
            services = response.json()
            if len(services) > 0:
                log(f"✅ Service '{SERVICE_NAME}' is registered")
                global service_was_registered
                service_was_registered = True
                break
        except:
            pass
        time.sleep(1)

    time.sleep(2)

def monitor_consul_blocking():
    global service_was_registered

    log(f"🔍 [{get_timestamp()}] Starting Consul blocking query monitor...")

    index = 0

    while True:
        try:
            response = requests.get(
                f"{CONSUL_URL}/v1/catalog/service/{SERVICE_NAME}",
                params={"wait": "60s", "index": index},
                timeout=65
            )

            new_index = response.headers.get('X-Consul-Index')

            if new_index and int(new_index) > index:
                timestamp = get_timestamp()
                services = response.json()

                log(f"📡 [{timestamp}] Blocking query returned (index: {index} -> {new_index}, services: {len(services)})")

                if len(services) == 0 and service_was_registered and events["consul_deregister_time"] is None:
                    events["consul_deregister_time"] = timestamp
                    log(f"✅ [{timestamp}] CONSUL DEREGISTERED SERVICE")

                if len(services) > 0:
                    service_was_registered = True

                index = int(new_index)

        except requests.exceptions.Timeout:
            pass
        except Exception as e:
            log(f"❌ Consul monitor error: {e}")
            time.sleep(1)

def monitor_consul_health():
    log(f"🔍 [{get_timestamp()}] Starting Consul health monitor...")

    last_status = "passing"

    while True:
        try:
            response = requests.get(f"{CONSUL_URL}/v1/health/service/{SERVICE_NAME}", timeout=2)
            checks = response.json()

            if checks:
                for check in checks:
                    for health_check in check.get('Checks', []):
                        status = health_check.get('Status')
                        if status != last_status:
                            timestamp = get_timestamp()
                            if status == "critical" and events["health_check_fail_time"] is None:
                                events["health_check_fail_time"] = timestamp
                                log(f"💔 [{timestamp}] HEALTH CHECK FAILED")
                            last_status = status

            time.sleep(0.5)

        except Exception as e:
            time.sleep(1)

def monitor_traefik():
    global service_was_registered

    log(f"🔍 [{get_timestamp()}] Starting Traefik monitor...")

    service_exists = None
    last_config_hash = None

    while True:
        try:
            response = requests.get(f"{TRAEFIK_URL}/api/http/services", timeout=2)
            services = response.json()

            # Вычисляем хэш конфигурации
            service_names = sorted([s.get('name', '') for s in services])
            config_hash = hash(str(service_names))

            # Ищем наш сервис
            found = False
            for service in services:
                service_name = service.get('name', '')
                if SERVICE_NAME in service_name and 'consulcatalog' in service_name:
                    found = True
                    break

            # Инициализация
            if service_exists is None and service_was_registered:
                service_exists = found
                last_config_hash = config_hash
                if found:
                    log(f"✅ [{get_timestamp()}] Traefik has service '{SERVICE_NAME}@consulcatalog'")

            # Детектируем изменение конфигурации
            if last_config_hash is not None and config_hash != last_config_hash:
                timestamp = get_timestamp()
                log(f"🔄 [{timestamp}] Traefik configuration changed")

                # Если сервис исчез
                if not found and service_exists and events["traefik_update_time"] is None:
                    events["traefik_update_time"] = timestamp
                    log(f"✅ [{timestamp}] TRAEFIK REMOVED SERVICE")
                    service_exists = False

                last_config_hash = config_hash

            time.sleep(0.5)

        except Exception as e:
            time.sleep(1)

def print_summary():
    log("\n" + "="*70)
    log("📊 TIMING SUMMARY")
    log("="*70)

    if events["health_check_fail_time"]:
        log(f"1️⃣  Health check failed:     {events['health_check_fail_time']}")
    else:
        log(f"1️⃣  Health check failed:     NOT DETECTED")

    if events["consul_deregister_time"]:
        log(f"2️⃣  Consul deregistered:      {events['consul_deregister_time']}")
    else:
        log(f"2️⃣  Consul deregistered:      NOT DETECTED")

    if events["traefik_update_time"]:
        log(f"3️⃣  Traefik updated:          {events['traefik_update_time']}")
    else:
        log(f"3️⃣  Traefik updated:          NOT DETECTED")

    log("")

    if events["consul_deregister_time"] and events["traefik_update_time"]:
        try:
            consul_time = datetime.strptime(events["consul_deregister_time"], "%Y-%m-%dT%H:%M:%S.%fZ")
            traefik_time = datetime.strptime(events["traefik_update_time"], "%Y-%m-%dT%H:%M:%S.%fZ")

            delay = (traefik_time - consul_time).total_seconds()

            log(f"⚡ LONG POLLING DELAY: {delay:.3f} seconds")
            log("")

            if delay < 0:
                log("⚠️  Negative delay - Traefik detected before Consul!")
                log("    This means Traefik's health check detected it first")
            elif delay < 1:
                log("✅ Excellent! Long polling worked instantly!")
            elif delay < 2:
                log("✅ Good! Long polling is fast.")
            else:
                log("⚠️  Delay detected.")
        except Exception as e:
            log(f"Error calculating delay: {e}")

    log("="*70 + "\n")

if __name__ == '__main__':
    log("="*70)
    log("🚀 MONITOR STARTING")
    log("="*70)
    log(f"   Consul: {CONSUL_URL}")
    log(f"   Traefik: {TRAEFIK_URL}")
    log(f"   Service: {SERVICE_NAME}")
    log("")

    wait_for_services()

    threading.Thread(target=monitor_consul_blocking, daemon=True).start()
    threading.Thread(target=monitor_consul_health, daemon=True).start()
    threading.Thread(target=monitor_traefik, daemon=True).start()

    log("✅ All monitors started")
    log("🎯 Waiting for service kill event...\n")

    try:
        summary_printed = False
        while True:
            time.sleep(5)

            if all(events.values()) and not summary_printed:
                print_summary()
                summary_printed = True

    except KeyboardInterrupt:
        log("\n👋 Monitoring stopped")
