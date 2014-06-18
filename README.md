All dates have to be in [ISO 8601](http://en.wikipedia.org/wiki/ISO_8601)

Start influx db
influxdb -config=/usr/local/etc/influxdb.conf

Access influx db
http://localhost:8083/

Start rabbitmq
rabbitmq-server



EXTENSION MODEL

monitor

scaler

Core
- has an argument -- queu anem
- must answer to instances
- must read queues to monitor


DICIONARIO MONITOR
:metric_name ==> [cpu_usage(%)|request_count]
:statistics ==> [[min|max|avg],[]]
:start_time ==> time in ???
:end_time ==> time in ???
:period ==> time  ---> SHORTCUTS:  FULL - EACH SECOND ; CONDENSED - ALL PERIOD IN ONE METRIC






---- TODO ----

SCALING DE LOAD BALANCERS?? para já assumimos que 1 LB funciona para tudo
API PARA DAR ORDENS AO DECIDER PARA FAZER ACCOES
DETAIL/CONDENSED PER INSTANCE?
NIVEIS DE INSTANCIAS PARA VERTICAL SCALING DOWN_UP

SCALER
-STARTUP TIME ON ANSWER FROM SCALER
-TEMPO DE BOOT DEVERA SER MEDIA? MODA? MEDIANA?

MONITOR
-DEFINIR REPLY QUEUE E PASSAR APENAS O FANOUT?
-APLICAR DICIONARIO AWS
-LIDAR COM ERROS DO LADO DO MONITOR
-PEDIR MAIS QUE UMA METRICA AO MESMO TEMPO?






