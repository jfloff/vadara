# Vadara

## Install

## Configure

Start influx db
influxdb -config=/usr/local/etc/influxdb.conf

Access influx db
http://localhost:8083/

Start rabbitmq
rabbitmq-server

## Run

## API
All dates have to be in second epoch (date in seconds since 1970 - UNIX STYLE)


DICIONARIO MONITOR
:metric_name ==> [cpu_usage(%)|request_count]
:statistics ==> [[min|max|avg],[]]
:start_time ==> time in ???
:end_time ==> time in ???
:period ==> time
:detail ==> detailed|condensed
