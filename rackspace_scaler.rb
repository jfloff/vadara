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
  rackspace_username: config['cps']['rackspace']['username'],
  rackspace_api_key: config['cps']['rackspace']['api_key'],
  version: :v2,
  rackspace_region: config['cps']['rackspace']['region'].downcase.to_sym,
  rackspace_auth_url: config['cps']['rackspace']['auth_url']
}

compute = Fog::Compute.new(credentials)

server = compute.servers.create(
  name: config['cps']['rackspace']['instance']['name'],
  flavor_id: config['cps']['rackspace']['instance']['flavor_id'],
  image_id: config['cps']['rackspace']['instance']['image_id'],
  metadata: {
    vadara: 'vadara'
  }
)
