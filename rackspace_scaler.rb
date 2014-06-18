#!/usr/bin/env ruby
# encoding: utf-8
require 'bunny'
require 'json'
require 'yaml'
require 'fog'
require 'time'
# require_relative "monitor_request"

config = YAML.load_file('config.yml')
config2 = YAML.load_file('/Users/jfloff/Code/vadara/cps/rackspace/rackspace.yml')

# create queue connections
# conn = Bunny.new(automatically_recover: false)
# conn.start

# channel = conn.create_channel
# channel_fanout = channel.fanout(config['queues']['monitor']['fanout'])
# aws_queue = channel.queue(config['queues']['monitor']['rackspace']).bind(channel_fanout)
# reply_queue = channel.queue(config['queues']['monitor']['reply'])

# rackspace compute config

credentials = {
  provider: 'Rackspace',
  rackspace_username: config2['username'],
  rackspace_api_key: config2['api_key'],
  version: :v2,
  rackspace_region: config2['region'].downcase.to_sym,
  rackspace_auth_url: config2['auth_url']
}

compute = Fog::Compute.new(credentials)

server = compute.servers.create(
  name: config2['instance']['name'],
  flavor_id: config2['instance']['flavor_id'],
  image_id: config2['instance']['image_id'],
  metadata: {
    vadara: 'vadara'
  }
)

while compute.get_server(server.id).body['server']['status'] != 'ACTIVE'
  sleep(10)
end

options = {
  rackspace_username: config2['username'],
  rackspace_api_key: config2['api_key'],
  rackspace_auth_url: config2['auth_url'],
  rackspace_region: config2['region'].downcase.to_sym,
}
monitoring = Fog::Rackspace::Monitoring.new(options)

created = false
until created
  monitoring.entities.all.each do |entity|
    if entity.agent_id == server.id
      check_info = monitoring.create_check(entity.id, type: 'agent.cpu')

      # in the location header, the end of the URL is the created check_id
      check_id = check_info.headers['Location'].rpartition('/')[2]

      # to write
      # entity.id, check_id

      available_at = Time.now
      created = true
    end
  end
end
