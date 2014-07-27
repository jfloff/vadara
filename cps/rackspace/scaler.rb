require 'yaml'
require 'json'
require 'bunny'
require 'fog'
require 'require_all'
require 'active_support/core_ext/time'
require_rel 'scaler_request.rb'

module RackspaceVadara
  class Scaler

    def initialize entities, lock, min_bootup_time
      @config = YAML.load_file(File.dirname(__FILE__) + '/rackspace.yml')

      @entities = entities
      @lock = lock

      options = {
        provider: 'Rackspace',
        rackspace_username: @config['username'],
        rackspace_api_key: @config['api_key'],
        version: :v2,
        rackspace_region: @config['region'].downcase.to_sym,
        rackspace_auth_url: @config['auth_url']
      }
      @compute = Fog::Compute.new(options)

      options = {
        rackspace_username: @config['username'],
        rackspace_api_key: @config['api_key'],
        rackspace_auth_url: @config['auth_url'],
        rackspace_region: @config['region'].downcase.to_sym,
      }
      @monitoring = Fog::Rackspace::Monitoring.new(options)
      @load_balancers = Fog::Rackspace::LoadBalancers.new(options)

      @min_bootup_time = min_bootup_time
    end

    def run(request_queue_name, reply_queue_name, fanout)
      return Thread.new {
        # init channel
        conn = Bunny.new(automatically_recover: false)
        conn.start
        channel = conn.create_channel

        # fanout for exchange
        channel_fanout = channel.fanout(fanout)

        # queues
        reply_queue = channel.queue(reply_queue_name)
        provider_queue = channel.queue('').bind(channel_fanout)

        begin
          puts " [rackspace][scaler] Waiting for messages"
          provider_queue.subscribe(:block => true) do |delivery_info, properties, payload|

            # request
            request = request(payload)

            puts " [rackspace][scaler] Received request"

            # reply to queue
            next if (reply = reply(request)).nil?

            # send reply to queue
            channel.default_exchange.publish(JSON.generate(reply),
              routing_key: reply_queue.name,
              headers: { vadara: { provider: 'rackspace' } },
              correlation_id: properties.correlation_id
            )
            puts " [rackspace][scaler] Sent reply!"
          end
        rescue Interrupt => _
          puts "[rackspace][scaler] Closing connection."
          conn.close
          Thread.exit
        end
      }
    end

    private
      def request(body)
        return ScalerRequest.new  JSON.parse(body)
      end

      def reply(request)

        horizontal_scale_down(request.horizontal_scale_down)
        new_instances = horizontal_scale_up(request.horizontal_scale_up)

        return new_instances.empty? ? nil : { new_instances: new_instances }
      end

      def horizontal_scale_up(n)

        instance_details = {
          name: @config['instance']['name'],
          flavor_id: @config['instance']['flavor_id'],
          image_id: @config['instance']['image_id'],
          metadata: {@config['instance']['key'] => @config['instance']['value']}
        }

        new_instances = Array.new
        n.times do
          server = @compute.servers.create(instance_details)
          server_id = server.id

          sleep_time = @min_bootup_time
          loop do
            # 75% less than the min bootup time and each time decreases
            sleep(sleep_time *= 0.75)
            server = @compute.get_server(server_id)
            break if server.body['server']['status'] == 'ACTIVE'
          end

          server_created = Time.parse(server.body['server']['created'])

          created = false
          until created
            @monitoring.entities.all.each do |entity|
              if entity.agent_id == server_id
                check_info = @monitoring.create_check(entity.id, type: 'agent.cpu')

                # in the location header, the end of the URL is the created check_id
                check_id = check_info.headers['Location'].rpartition('/')[2]

                # to write
                @lock.synchronize{
                  @entities[entity.id] = { cpu_check_id: check_id }
                }

                bootup_time = Time.now - server_created
                new_instances << { instance_id: server_id, launch_time: server_created.to_i, bootup_time: bootup_time }

                # new min
                @min_bootup_time = bootup_time if @min_bootup_time > bootup_time
                created = true
              end
            end
          end

          # intenal IPcc
          ip = server.body['server']['addresses']['private'][0]['addr']
          # add internal machine to LB
          @load_balancers.create_node(@config['load_balancer']['id'], ip, @config['load_balancer']['port'], 'ENABLED')
        end

        return new_instances
      end

      def horizontal_scale_down(to_delete)

        return if to_delete.empty?

        # deregister fom LB
        @load_balancers.delete_nodes(@config['load_balancer']['id'], to_delete)

        # delete servers
        to_delete.each do |server_id|
          @compute.delete_server(server_id)
        end
      end
  end
end
