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

options = {
  provider: 'Rackspace',
  rackspace_username: config['cloud_providers']['rackspace']['username'],
  rackspace_api_key: config['cloud_providers']['rackspace']['api_key'],
  rackspace_auth_url: config['cloud_providers']['rackspace']['auth_url'],
  rackspace_region: config['cloud_providers']['rackspace']['region'].downcase.to_sym,
  version: :v2
}

compute = Fog::Compute.new(options)

instance_tag = config['instance_tag']
servers_ids  = Array.new

compute.servers.each do |server|
  server.metadata.each do |metadatum|
    servers_ids << server.id if(metadatum.key == instance_tag)
  end
end

print YAML::dump(servers_ids)


monitoring = Fog::Rackspace::Monitoring.new(options)
print monitoring.entities.all
print monitoring.check_types.all

# monitoring = Fog::Monitoring::Rackspace.new(credentials[:api_key], credentials[:rackspace_username])
# puts monitoring.entities.overview
