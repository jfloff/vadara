require 'yaml'
require 'json'
require 'aws-sdk-core'
require 'require_all'
require 'bunny'
require_rel 'monitor.rb'

module AwsVadara
  class Core

    def initialize
      @config = YAML.load_file(File.dirname(__FILE__) + '/aws.yml')

      Aws.config = {
        access_key_id: @config['access_key_id'],
        secret_access_key: @config['secret_access_key'],
        region: @config['region']
      }
    end


    def run(queue_name)
      puts " [aws][core] Starting ..."
      conn = Bunny.new
      conn.start
      # create a default exchange for the publish
      ch = conn.create_channel
      x = ch.default_exchange
      # create a reply queue
      reply_queue = ch.queue("", exclusive: true)

      # publish instances from AWS
      instances_data = instances
      puts " [aws][core] Sent instances details"
      x.publish(JSON.generate(instances_data), routing_key: queue_name, reply_to: reply_queue.name)

      queues_data = nil
      reply_queue.subscribe(:block => true) do |delivery_info, properties, payload|
        # the answer is the queues for monitor/scaler
        queues_data = JSON.parse(payload)
        puts " [aws][core] Received queues detail"

        ch.close
      end
      conn.close

      ids = instances_ids(instances_data)

      puts " [aws][core] Starting aws provider services!"

      # starts the monitor
      start_monitor(queues_data['request'], queues_data['reply'], queues_data['fanout'], ids)

      puts " [aws][core] aws provider ready!"
    end

    private
      def instances
        ec2 = Aws::EC2.new

        # http://docs.aws.amazon.com/sdkforruby/api/frames.html
        resp = ec2.describe_instances(
          filters: [
            # instances tagged with vadara
            {
              name: 'tag:' + @config['instance']['key'],
              values: [@config['instance']['value']]
            },
            # filter only pending or running instances
            {
              name: 'instance-state-code',
              values: ['0','16']
            }
          ]
        )

        instances = Array.new
        resp['reservations'].each do |reservation|
          reservation['instances'].each do |instance|
            # write instance creation into db
            instances << {
              instance_id: instance.instance_id,
              time: instance.launch_time.to_i
            }
          end
        end

        return instances
      end

      def instances_ids(instances)
        ids = Array.new
        instances.each do |instance|
          ids << instance[:instance_id]
        end
        return ids
      end

      def start_monitor(request, reply, fanout, ids)
        puts " [aws][core] Starting Monitor ..."

        monitor = AwsVadara::Monitor.new ids
        monitor.run(request, reply, fanout)
      end
  end
end

queue_name = ARGV[0]

aws = AwsVadara::Core.new
aws.run queue_name
