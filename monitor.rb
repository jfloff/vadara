#!/usr/bin/env ruby
# encoding: utf-8

require 'bunny'
require 'json'
require 'YAML'
require_relative "monitor_request"

# Receiver thread
Thread.new do
  config = YAML.load_file('config.yml')

  conn = Bunny.new(:automatically_recover => false)
  conn.start

  providers_channel = conn.create_channel
  providers_reply_queue = providers_channel.queue(config['queues']['monitor']['reply'])

  begin
    puts " [*] Waiting for reply from Cloud Providers"
    providers_reply_queue.subscribe(:block => false) do |delivery_info, properties, body|
      request = JSON.parse(body)
      puts request.to_json
    end

  rescue Interrupt => _
    conn.close
    exit(0)
  end
end

config = YAML.load_file('config.yml')

conn = Bunny.new(:automatically_recover => false)
conn.start

monitor_channel = conn.create_channel
monitor_queue = monitor_channel.queue(config['queues']['monitor']['request'])

providers_channel = conn.create_channel
providers_channel_fanout = providers_channel.fanout(config['queues']['monitor']['fanout'])

begin
  puts " [*] Waiting for messages. To exit press CTRL+C"
  monitor_queue.subscribe(:block => true) do |delivery_info, properties, body|
    request_json = JSON.parse(body)

    request = MonitorRequest.new
    request.from_json! request_json

    providers_channel_fanout.publish(request.to_json)
    puts " [x] Sent 'Cloud Provider Monitor Request!'"
    puts request.to_json
  end

rescue Interrupt => _
  conn.close
  exit(0)
end

# Receiver-thread
