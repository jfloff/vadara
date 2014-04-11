#!/usr/bin/env ruby
# encoding: utf-8

require 'bunny'
require 'json'
require 'aws-sdk-core'
require 'yaml'
require_relative "monitor_request"

conn = Bunny.new(:automatically_recover => false)
conn.start

channel = conn.create_channel
queue = channel.queue("aws")

config = YAML.load_file('config.yml')

Aws.config = {
  access_key_id: config['cloud_providers']['aws']['access_key_id'],
  secret_access_key: config['cloud_providers']['aws']['secret_access_key'],
  region: config['cloud_providers']['aws']['region']
}

cw = Aws::CloudWatch.new

begin
  puts " [*] Waiting for messages. To exit press CTRL+C"
  queue.subscribe(:block => true) do |delivery_info, properties, body|
    request_json = JSON.parse(body)

    request = MonitorRequest.new
    request.from_json! request_json

    instance_id = 'i-e5281aa4'

    result = cw.get_metric_statistics(
      namespace: 'AWS/EC2',
      metric_name: request.metric_name,
      statistics: request.statistics,
      start_time: request.start_time,
      end_time: request.end_time,
      period: request.period
      # dimensions: [{name: 'InstanceId', value: "#{instance_id}"}]
    )

    puts 'AWS RESULT = ' + YAML::dump(result)
  end

rescue Interrupt => _
  conn.close
  exit(0)
end
