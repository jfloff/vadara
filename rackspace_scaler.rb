#!/usr/bin/env ruby
# encoding: utf-8
require 'bunny'
require 'json'
require 'yaml'
require 'fog'
require_relative "monitor_request"

config = YAML.load_file('config.yml')

# create queue connections
conn = Bunny.new(automatically_recover: false)
conn.start

channel = conn.create_channel
channel_fanout = channel.fanout(config['queues']['monitor']['fanout'])
aws_queue = channel.queue(config['queues']['monitor']['rackspace']).bind(channel_fanout)
reply_queue = channel.queue(config['queues']['monitor']['reply'])

# rackspace compute config

credentials = {
  provider: 'Rackspace',
  rackspace_username: config['cloud_providers']['rackspace']['username'],
  rackspace_api_key: config['cloud_providers']['rackspace']['api_key'],
  version: :v2,
  rackspace_region: config['cloud_providers']['rackspace']['region'].downcase.to_sym,
  rackspace_auth_url: config['cloud_providers']['rackspace']['auth_url']
}

compute = Fog::Compute.new(credentials)

server = compute.servers.create(
  name: config['cloud_providers']['rackspace']['instance']['name'],
  flavor_id: config['cloud_providers']['rackspace']['instance']['flavor_id'],
  image_id: config['cloud_providers']['rackspace']['instance']['image_id'],
  metadata: {
    vadara: 'vadara'
  }
)
