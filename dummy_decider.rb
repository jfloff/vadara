#!/usr/bin/env ruby
# encoding: utf-8

require "rubygems"
require "bunny"
require "json"
require_relative "monitor_request"
require "YAML"

##
# Connects to RabbitMQ running on localhost, with default values
# Port: 5672
# Username: guest
# Password: guest
# Virtual host: /
##

conn = Bunny.new(:automatically_recover => false)
conn.start

ch = conn.create_channel
q = ch.queue("monitor")

request = MonitorRequest.new
request.metric_name = 'CPUUtilization'
request.statistics = ['Average']
time = Time.new
time.gmtime
request.start_time = time-1000
request.end_time = time+1000
request.period = 60

request_json = request.to_json

ch.default_exchange.publish(request_json, :routing_key => q.name)
puts " [x] Sent 'Monitor Request!'"

conn.close
