require 'yaml'
require 'json'
require 'bunny'
require 'fog'
require 'require_all'
require_rel 'monitor.rb'

module RackspaceVadara
  class Core

    def initialize
      @config = YAML.load_file(File.dirname(__FILE__) + '/rackspace.yml')
    end


    def run(queue_name)
      puts " [rackspace][core] Starting ..."
      conn = Bunny.new
      conn.start
      # create a default exchange for the publish
      ch = conn.create_channel
      x = ch.default_exchange
      # create a reply queue
      reply_queue = ch.queue("", exclusive: true)

      # publish instances from AWS
      instances_data = instances
      puts " [rackspace][core] Sent instances details"
      x.publish(JSON.generate(instances_data), routing_key: queue_name, reply_to: reply_queue.name)

      queues_data = nil
      reply_queue.subscribe(:block => true) do |delivery_info, properties, payload|
        # the answer is the queues for monitor/scaler
        queues_data = JSON.parse(payload)
        puts " [rackspace][core] Received queues detail"

        ch.close
      end
      conn.close

      info = entities_info(instances_data)

      puts " [rackspace][core] Starting rackspace provider services!"

      # starts the monitor
      start_monitor(queues_data['request'], queues_data['reply'], queues_data['fanout'], info)

      puts " [rackspace][core] rackspace provider ready!"
    end

    private
      def instances
        # rackspace compute config
        options = {
          provider: 'Rackspace',
          rackspace_username: @config['username'],
          rackspace_api_key: @config['api_key'],
          rackspace_auth_url: @config['auth_url'],
          rackspace_region: @config['region'].downcase.to_sym,
          version: :v2
        }
        compute = Fog::Compute.new(options)

        servers  = Array.new
        compute.servers.each do |server|
          if server_belongs?(server)
            servers << {
              instance_id: server.id,
              time: Time.parse(server.created).to_i
            }
          end
        end

        return servers
      end

      def server_belongs?(server)
        check_state = (server.state != 'DELETED' and server.state != 'ERROR' and server.state != 'SUSPENDED')

        check_metadata = false
        server.metadata.each do |metadatum|
          if(metadatum.key == @config['instance']['key'] and metadatum.value == @config['instance']['value'])
            check_metadata = true
            break
          end
        end

        return (check_state and check_metadata)
      end

      def entities_info(instances)
        ids = []
        instances.each do |instance|
          ids << instance[:instance_id]
        end

        # init monitoring
        options = {
          rackspace_username: @config['username'],
          rackspace_api_key: @config['api_key'],
          rackspace_auth_url: @config['auth_url'],
          rackspace_region: @config['region'].downcase.to_sym,
        }
        monitoring = Fog::Rackspace::Monitoring.new(options)

        info = []
        monitoring.entities.all.each do |entity|
          if ids.include? entity.agent_id
            entity_info = {}

            entity_info[:entity_id] = entity.id

            monitoring.list_checks(entity.id).body['values'].each do |check|
              if check['type'] == 'agent.cpu'
                entity_info[:cpu_check_id] = check['id']
              end
            end

            info << entity_info
          end
        end

        return info
      end

      def start_monitor(request, reply, fanout, info)
        puts " [rackspace][core] Starting Monitor ..."

        monitor = RackspaceVadara::Monitor.new info
        monitor.run(request, reply, fanout)
      end
  end
end

queue_name = ARGV[0]

rackspace = RackspaceVadara::Core.new
rackspace.run queue_name
