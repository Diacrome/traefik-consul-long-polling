Запуск

./test-longpolling-manual.sh

смотреть лог в консоли и 

`docker-compose logs traefik | grep -i "Configuration received" | tail -5`

получится так
```
12:29:25.000 - Service killed

12:29:26.000 - Consul health check failed (реально)
12:29:26.000 - Traefik получил уведомление через blocking query
12:29:26.867 - Монитор детектировал (через polling с задержкой 0.867s)

12:29:30.000 - Consul deregister (реально)
12:29:30.000 - Traefik получил уведомление через blocking query
12:29:30.640 - Монитор детектировал (через polling с задержкой 0.640s)
```
