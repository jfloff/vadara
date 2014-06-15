#!/usr/bin/env ruby
# encoding: utf-8

require 'rubygems'
require 'bunny'
require 'json'
require 'yaml'
require 'time'
require 'require_all'
require_all 'monitor/monitor_request.rb'
require_rel 'scaler_request'

##
# Connects to RabbitMQ running on localhost, with default values
# Port: 5672
# Username: guest
# Password: guest
# Virtual host: /
##

config = YAML.load_file('config.yml')

conn = Bunny.new(:automatically_recover => false)
conn.start

monitor_ch = conn.create_channel
monitor_q = monitor_ch.queue(config['queues']['monitor']['request'])

scaler_ch = conn.create_channel
scaler_q = scaler_ch.queue(config['queues']['scaler']['request'])

request = Vadara::MonitorRequest.new
request.metric_name = 'CPUUtilization'
request.statistics = ['Average']
time = Time.new
request.start_time = (time-8000).iso8601
request.end_time = time.iso8601
request.period = 120

request_json = request.to_json

monitor_ch.default_exchange.publish(request_json, :routing_key => monitor_q.name)
puts " [x] Sent 'Monitor Request!'"

# request = MonitorRequest.new
# request.metric_name = 'RequestCount'
# request.statistics = ['Sum']
# time = Time.new
# request.start_time = (time-8000).iso8601
# request.end_time = time.iso8601
# request.period = 120

# request_json = request.to_json

# monitor_ch.default_exchange.publish(request_json, :routing_key => monitor_q.name)
# puts " [x] Sent 'Monitor Request!'"

# request = ScalerRequest.new
# request.scale_up = 1
# request.scale_down = 0

# request_json = request.to_json

# scaler_ch.default_exchange.publish(request_json, :routing_key => scaler_q.name)
# puts " [x] Sent 'Scaler Request!'"



conn.close
