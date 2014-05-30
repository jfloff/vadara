#!/usr/bin/env ruby
# encoding: utf-8

require 'bunny'
require 'json'
require 'aws-sdk-core'
require 'yaml'
require_relative 'scaler_request'

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
      ids << instance.instance_id
    end
  end

  return ids
end

config = YAML.load_file('config.yml')

conn = Bunny.new(automatically_recover: false)
conn.start

channel = conn.create_channel
channel_fanout = channel.fanout(config['queues']['scaler']['fanout'])
aws_queue = channel.queue(config['queues']['scaler']['aws']).bind(channel_fanout)
reply_queue = channel.queue(config['queues']['scaler']['reply'])

Aws.config = {
  access_key_id: config['cloud_providers']['aws']['access_key_id'],
  secret_access_key: config['cloud_providers']['aws']['secret_access_key'],
  region: config['cloud_providers']['aws']['region']
}

created_instances_ids = instances_ids()

ec2 = Aws::EC2.new
begin
  puts " [*] Waiting for messages. To exit press CTRL+C"
  aws_queue.subscribe(:block => true) do |delivery_info, properties, body|
    request_json = JSON.parse(body)

    request = ScalerRequest.new
    request.from_json! request_json

    puts request_json

    if request.scale_up > 0
      resp = ec2.run_instances({
          image_id: config['cloud_providers']['aws']['instance']['image_id'],
          min_count: request.scale_up,
          max_count: request.scale_up,
          key_name: config['cloud_providers']['aws']['instance']['key_name'],
          instance_type: config['cloud_providers']['aws']['instance']['instance_type'],
      })

      new_instances_ids = Array.new

      resp.instances.each do |instance|
        new_instances_ids << instance.instance_id
      end

      created_instances_ids.concat(new_instances_ids)

      resp = ec2.create_tags(
        resources: new_instances_ids,
        tags: [
          {
            key: config['instance_tag']['key'],
            value: config['instance_tag']['value']
          }
        ]
      )
    end

    if request.scale_down > 0
      resp = ec2.terminate_instances(
        instance_ids: created_instances_ids.first(request.scale_down),
      )
    end
  end

rescue Interrupt => _
  conn.close
  exit(0)
end

