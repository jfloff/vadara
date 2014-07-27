require 'yaml'
require 'json'
require 'bunny'
require 'aws-sdk-core'
require 'require_all'
require 'active_support/core_ext/time'
require_rel 'scaler_request.rb'

module AwsVadara
  class Scaler

    def initialize instances, lock, min_bootup_time
      @config = YAML.load_file(File.dirname(__FILE__) + '/aws.yml')

      @instances = instances
      @lock = lock
      @min_bootup_time = min_bootup_time

      Aws.config = {
        access_key_id: @config['access_key_id'],
        secret_access_key: @config['secret_access_key'],
        region: @config['region']
      }

      @ec2 = Aws::EC2.new
      @lb = Aws::ElasticLoadBalancing.new
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
          puts " [aws][scaler] Waiting for messages"
          provider_queue.subscribe(:block => true) do |delivery_info, properties, payload|

            # request
            puts " [aws][scaler] Received request"
            request = request(payload)

            # reply to queue
            next if (reply = reply(request)).nil?

            # send reply to queue
            channel.default_exchange.publish(JSON.generate(reply),
              routing_key: reply_queue.name,
              headers: { vadara: { provider: 'aws' } },
              correlation_id: properties.correlation_id
            )
            puts " [aws][scaler] Sent reply!"
          end
        rescue Interrupt => _
          puts "[asw][scaler] Closing connection."
          conn.close
          Thread.exit
        end
      }
    end

    private
      def request(body)
        return ScalerRequest.new JSON.parse(body)
      end

      def reply(request)

        horizontal_scale_down(request.horizontal_scale_down)
        new_instances = horizontal_scale_up(request.horizontal_scale_up)

        return new_instances.empty? ? nil : { new_instances: new_instances }
      end

      def horizontal_scale_up(n)

        new_instances = Array.new

        # returns
        return new_instances if n <= 0

        n.times do
          resp = @ec2.run_instances(
            image_id: @config['instance']['image_id'],
            min_count: 1,
            max_count: 1,
            key_name: @config['instance']['key_name'],
            instance_type: @config['instance']['instance_type'],
          )

          instance = resp.instances[0]
          instance_created = instance.launch_time

          sleep_time = @min_bootup_time
          loop do
            # 75% less than the min bootup time and each time decreases
            sleep(sleep_time *= 0.75)

            status = @ec2.describe_instance_status(instance_ids: [instance.instance_id])
            if status.instance_statuses.empty?
              next
            end
            break if status.instance_statuses[0].instance_state.code == 16
          end

          bootup_time = Time.now - instance_created

          # new min
          @min_bootup_time = bootup_time if @min_bootup_time > bootup_time

          new_instances << {
            instance_id: instance.instance_id,
            launch_time: instance_created.to_i,
            bootup_time: bootup_time
          }
        end

        tag_ids = Array.new
        lb_ids = Array.new
        new_instances.each do |instance|
          instance_id = instance[:instance_id]

          tag_ids << instance_id
          lb_ids << { instance_id: instance_id }
          @lock.synchronize{ @instances[instance_id] = {} }
        end

        # add tags to isntances
        @ec2.create_tags(
          resources: tag_ids,
          tags: [
            {
              key: @config['instance']['key'],
              value: @config['instance']['value']
            }
          ]
        )

        # register with LB
        @lb.register_instances_with_load_balancer(
          load_balancer_name: @config['load_balancer']['name'],
          instances: lb_ids
        )

        return new_instances
      end

      def horizontal_scale_down(to_delete)

        return if to_delete.empty?

        # de-register nodes from LB
        lb_ids = to_delete.map { |instance_id| { instance_id: instance_id } }

        @lb.deregister_instances_from_load_balancer(
          load_balancer_name: @config['load_balancer']['name'],
          instances: lb_ids
        )

        # delete instances
        @ec2.terminate_instances(instance_ids: to_delete)
      end
  end
end
