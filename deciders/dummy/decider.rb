#!/usr/bin/env ruby
# encoding: utf-8

require 'bunny'
require 'json'
require 'yaml'
require 'time'

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

if ARGV[0] == 'monitor'

  #########################################################################################
  ####################################### MONITOR #########################################
  #########################################################################################

  monitor_ch = conn.create_channel
  monitor_q = monitor_ch.queue(config['queues']['monitor']['request'])

  decider_ch = conn.create_channel
  decider_queue = decider_ch.queue(config['queues']['decider']['reply'], :exclusive => true)

  now = Time.now

  # CPU
  cpu = {
    'metric_name' => 'cpu_usage',
    'statistics' => ['avg'],
    'start_time' => (now-120).to_i,
    'end_time' => now.to_i,
    'period' => 120,
    'detail' => 'condensed',
  }
  # REQUESTS
  request_count = {
    'metric_name' => 'request_count',
    'statistics' => [],
    'start_time' => (now-120).to_i,
    'end_time' => now.to_i,
    'period' => 120,
    'detail' => 'condensed',
  }

  requests = [cpu, request_count].to_json

  monitor_ch.default_exchange.publish(requests, :routing_key => monitor_q.name)
  puts " [x] Sent 'Monitor Request!'"

  decider_queue.subscribe(:block => true) do |delivery_info, properties, payload|
    puts " REPLY = " + payload
  end

elsif ARGV[0] == 'scaler'

  #########################################################################################
  ######################################## SCALER #########################################
  #########################################################################################

  scaler_ch = conn.create_channel
  scaler_q = scaler_ch.queue(config['queues']['scaler']['request'])

  request = {
    'horizontal_scale_up' => { 'aws' => 1  },
    'horizontal_scale_down' => { 'rackspace' => 2 }
  }.to_json

  scaler_ch.default_exchange.publish(request, :routing_key => scaler_q.name)
  puts " [x] Sent 'Scaler Request!'"
end

conn.close


loop do
  metrics_request = {
    'metric_name'  => ['cpu'],
    'statistics'   => ['avg'],
    'start_time'   => (now-600).to_i,
    'end_time'     => now.to_i,
    'period'       => 60,
    'aggregation' => 'condensed',
  }.to_json

  # publishes request to queue
  channel.default_exchange.publish(metrics_request, :routing_key => monitor_request.name)

  # waits response
  monitor_reply.subscribe(:block => true) do |delivery_info, properties, payload|
    # metrics for all providers
    metrics = JSON.parse(payload)
    #loops metrics for each provider
    metrics.each do |metric|
      provider = metric['provider']
      cpu_utilization = metric['cpu']

      scale_request = nil
      if cpu_utilization['cpu'] <= 30
        # if below 30% scales down
        scale_request = {'horizontal_scale_down' => { provider => 1 }}.to_json
      elsif cpu_utilization['cpu'] >= 70
        # if above 70% scales up
        scale_request = {'horizontal_scale_up' => { provider => 1 }}.to_json
      end

      if (!scale_request.nil?)
        scaler_ch.default_exchange.publish(scale_request, :routing_key => scaler_request.name)
        # 5 minute cooldown period
        sleep(300)
      end
    end
  end
end
