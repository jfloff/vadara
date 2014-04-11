#!/usr/bin/env ruby
# encoding: utf-8

require "bunny"
require "json"
require_relative "monitor_request"

conn = Bunny.new(:automatically_recover => false)
conn.start

monitor_channel = conn.create_channel
monitor_queue = monitor_channel.queue("monitor")

aws_channel = conn.create_channel
aws_queue = aws_channel.queue("aws")

begin
  puts " [*] Waiting for messages. To exit press CTRL+C"
  monitor_queue.subscribe(:block => true) do |delivery_info, properties, body|
    request_json = JSON.parse(body)

    request = MonitorRequest.new
    request.from_json! request_json

    aws_channel.default_exchange.publish(request.to_json, :routing_key => aws_queue.name)
    puts " [x] Sent 'AWS Monitor Request!'"
  end

rescue Interrupt => _
  conn.close
  exit(0)
end
