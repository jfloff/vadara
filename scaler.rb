#!/usr/bin/env ruby
# encoding: utf-8

require 'bunny'
require 'json'
require 'yaml'
require_relative 'monitor_request'
require_relative 'scaler_request'

config = YAML.load_file('config.yml')

conn = Bunny.new(:automatically_recover => false)
conn.start

scaler_channel = conn.create_channel
scaler_queue = scaler_channel.queue(config['queues']['scaler']['request'])

providers_channel = conn.create_channel
providers_channel_fanout = providers_channel.fanout(config['queues']['scaler']['fanout'])

begin
  puts " [*] Waiting for messages. To exit press CTRL+C"
  scaler_queue.subscribe(:block => true) do |delivery_info, properties, body|
    request_json = JSON.parse(body)

    request = ScalerRequest.new
    request.from_json! request_json

    providers_channel_fanout.publish(request.to_json)
    puts " [x] Sent 'Cloud Provider Scaler Request!'"
    puts request.to_json
  end

rescue Interrupt => _
  conn.close
  exit(0)
end

# Receiver-thread
