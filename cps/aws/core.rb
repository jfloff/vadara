require 'yaml'
require 'json'
require 'aws-sdk-core'
require 'require_all'
require 'bunny'
require_rel 'monitor.rb', 'scaler.rb'
require 'thread'

module AwsVadara
  class Core

    def initialize
      @config = YAML.load_file(File.dirname(__FILE__) + '/aws.yml')

      Aws.config = {
        access_key_id: @config['access_key_id'],
        secret_access_key: @config['secret_access_key'],
        region: @config['region']
      }

      @instances = Hash.new
      @lock = Mutex.new
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
      instances_data = instances()
      puts " [aws][core] Sent instances details"
      x.publish(JSON.generate(instances_data),
        headers: { vadara: { provider: 'aws' } },
        routing_key: queue_name,
        reply_to: reply_queue.name)

      queues_data = nil
      reply_queue.subscribe(:block => true) do |delivery_info, properties, payload|
        # the answer is the queues for monitor/scaler
        queues_data = JSON.parse(payload)
        puts " [aws][core] Received queues detail"

        ch.close
      end
      conn.close

      puts " [aws][core] Starting aws provider services!"

      # starts the monitor
      puts " [aws][core] Starting Monitor ..."
      monitor = AwsVadara::Monitor.new(@instances,@lock)
      monitor_t = monitor.run(queues_data['monitor']['request'],
        queues_data['monitor']['reply'],
        queues_data['monitor']['fanout'])

      # starts the scaler
      puts " [aws][core] Starting Scaler ..."
      scaler = AwsVadara::Scaler.new(@instances, @lock, queues_data['scaler']['min_bootup_time'])
      scaler_t = scaler.run(queues_data['scaler']['request'],
        queues_data['scaler']['reply'],
        queues_data['scaler']['fanout'])

      puts " [aws][core] aws provider ready!"

      # joins both threads
      # passes Interrupt on both
      begin
        monitor_t.join
        scaler_t.join
      rescue Interrupt => e
        monitor_t.raise e
        scaler_t.raise e
      end

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
            instances << {
              instance_id: instance.instance_id,
              launch_time: instance.launch_time.to_i
            }

            @instances[instance.instance_id] = {}
          end
        end

        return instances
      end
  end
end

queue_name = ARGV[0]

aws = AwsVadara::Core.new
aws.run queue_name
