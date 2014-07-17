require 'yaml'
require 'json'
require 'bunny'
require 'fog'
require 'require_all'
require_rel 'monitor.rb', 'scaler.rb'

module RackspaceVadara
  class Core

    def initialize
      @config = YAML.load_file(File.dirname(__FILE__) + '/rackspace.yml')
      @entities = Hash.new
      @lock = Mutex.new
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
      x.publish(JSON.generate(instances_data),
        headers: { vadara: { provider: 'rackspace' } },
        routing_key: queue_name,
        reply_to: reply_queue.name)

      queues_data = nil
      reply_queue.subscribe(:block => true) do |delivery_info, properties, payload|
        # the answer is the queues for monitor/scaler
        queues_data = JSON.parse(payload)
        puts " [rackspace][core] Received queues detail"

        ch.close
      end
      conn.close

      # add instances to entities
      add_entities_by_instances(instances_data)

      puts " [rackspace][core] Starting rackspace provider services!"

      # starts the monitor
      puts " [rackspace][core] Starting Monitor ..."
      monitor = RackspaceVadara::Monitor.new @entities, @lock
      monitor_t = monitor.run(queues_data['monitor']['request'],
        queues_data['monitor']['reply'],
        queues_data['monitor']['fanout'])

      # starts the scaler
      puts " [rackspace][core] Starting Scaler ..."
      scaler = RackspaceVadara::Scaler.new @entities, @lock, queues_data['scaler']['min_bootup_time']
      scaler_t = scaler.run(queues_data['scaler']['request'],
        queues_data['scaler']['reply'],
        queues_data['scaler']['fanout'])

      puts " [rackspace][core] rackspace provider ready!"

      # joins both threads
      # passes Interrupt on both
      begin
        monitor_t.join
        scaler_t.join
      rescue Interrupt => e
        monitor_t.raise e
        scaler_t.raise e
      end
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
              launch_time: Time.parse(server.created).to_i
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

      def add_entities_by_instances(instances)
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

        monitoring.entities.all.each do |entity|
          # check entities from the vadara's tagged instances
          if ids.include? entity.agent_id
            monitoring.list_checks(entity.id).body['values'].each do |check|
              # select only checks from agent.CPU
              if check['type'] == 'agent.cpu'
                # add entities to the
                @entities[entity.id] = { cpu_check_id: check['id'] }
              end
            end
          end
        end
      end
  end
end

queue_name = ARGV[0]

rackspace = RackspaceVadara::Core.new
rackspace.run queue_name
