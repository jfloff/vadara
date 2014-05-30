#!/usr/bin/env ruby
# encoding: utf-8

require 'bunny'
require 'json'
require 'aws-sdk-core'
require 'yaml'
require_relative "monitor_request"


def instances_ids()

  ec2 = Aws::EC2.new

  config = YAML.load_file('config.yml')

  resp = ec2.describe_instances(
    filters: [{
      name: 'tag:' + config['instance_tag']['key'],
      values: [config['instance_tag']['value']]
    }]
  )

  ids = Array.new

  resp['reservations'].each do |reservation|
    reservation['instances'].each do |instance|
      ids << {
        name: "InstanceId",
        value: instance.instance_id
      }
    end
  end

  return ids
end

config = YAML.load_file('config.yml')

conn = Bunny.new(automatically_recover: false)
conn.start

channel = conn.create_channel
channel_fanout = channel.fanout(config['queues']['monitor']['fanout'])
aws_queue = channel.queue(config['queues']['monitor']['aws']).bind(channel_fanout)
reply_queue = channel.queue(config['queues']['monitor']['reply'])

Aws.config = {
  access_key_id: config['cloud_providers']['aws']['access_key_id'],
  secret_access_key: config['cloud_providers']['aws']['secret_access_key'],
  region: config['cloud_providers']['aws']['region']
}

cw = Aws::CloudWatch.new

begin
  puts " [*] Waiting for messages. To exit press CTRL+C"
  aws_queue.subscribe(:block => true) do |delivery_info, properties, body|
    request_json = JSON.parse(body)

    request = MonitorRequest.new
    request.from_json! request_json

    if (request.metric_name = 'RequestCount')
      namespace = 'AWS/ELB'
      dimensions = [{
        name: "LoadBalancerName",
        value: config['cloud_providers']['aws']['load_balancer']['name']
      }]
    else
      namespace = 'AWS/EC2',
      dimensions = instances_ids()
    end

    options = {
      # http://docs.aws.amazon.com/AmazonCloudWatch/latest/DeveloperGuide/aws-namespaces.html
      namespace: namespace,
      metric_name: request.metric_name,
      statistics: request.statistics,
      start_time: request.start_time,
      end_time: request.end_time,
      period: request.period,
      dimensions: dimensions
    }

    result = cw.get_metric_statistics(options)

    datapoints_array = Array.new
    result[:datapoints].each do |datapoint|
      datapoints_array << datapoint.to_h
    end

    # Reply
    reply_json = JSON.generate(datapoints_array)
    channel.default_exchange.publish(reply_json, routing_key: reply_queue.name)
    puts " [x] Sent 'Monitor Reply!'"
  end

rescue Interrupt => _
  conn.close
  exit(0)
end

