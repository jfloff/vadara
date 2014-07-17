require 'bunny'
require 'json'
require 'require_all'
require 'securerandom'
require_rel 'scaler_request.rb'

module Vadara
  class Scaler

    def initialize(config,db)
      @config = config
      @db = db

      @conn = Bunny.new(automatically_recover: false)
      @conn.start

      @instances = Hash.new
      @bootup_times = Hash.new

      load_db_info
    end

    def run
      return Thread.new {
        begin
          reply_t = Thread.new { reply_to_decider }
          receive_t = Thread.new { receive_from_decider }

          reply_t.join
          receive_t.join
        rescue Interrupt => _
          @conn.close
          puts " [vadara][scaler] Closing connection"
          Thread.exit
        end
      }
    end

    private

      def receive_from_decider
        scaler_channel = @conn.create_channel
        scaler_queue = scaler_channel.queue(@config[:queues][:scaler][:request])

        providers_channel = @conn.create_channel
        providers_channel_fanout = providers_channel.fanout(@config[:queues][:scaler][:fanout])

        puts " [vadara][scaler] Waiting `decider` messages"
        scaler_queue.subscribe(:block => true) do |delivery_info, properties, payload|
          request = ScalerRequest.new JSON.parse(payload)

          request.horizontal_scale_down = instances_to_scale_down(request.horizontal_scale_down)

          correlation_id = SecureRandom.uuid
          providers_channel_fanout.publish(request.to_json, correlation_id: correlation_id)

          puts " [vadara][scaler] Sent CP request"
          puts " [vadara][scaler] request = " + request.to_json
        end
      end

      def instances_to_scale_down(request_scale_down)
        to_delete = Hash.new
        request_scale_down.each do |provider, n|
          # sort instances by time
          instances = @instances[provider].sort  { |x, y| x[:launch_time] <=> y[:launch_time] }

          if @config[:cps][provider.to_sym][:full_period_unit] == 'h'
          else
            to_delete[provider] = Array.new
            instances.shift(n).each do |instance|
              to_delete[provider] << instance[:instance_id]
            end
          end
        end
        return to_delete
      end

      def min_bootup_times
        reply = Hash.new
        @bootup_times.each do |provider, times|
          reply[provider] = times.min
        end
        return reply
      end

      def reply_to_decider
        providers_channel = @conn.create_channel
        providers_reply_queue = providers_channel.queue(@config[:queues][:scaler][:reply])

        instances_series = @config[:db][:instances_series]
        bootup_times_series = @config[:db][:bootup_times_series]

        puts " [vadara][scaler] Waiting CPs replies"
        providers_reply_queue.subscribe(:block => true) do |delivery_info, properties, payload|
          puts " [vadara][scaler] Received CP reply"

          provider = properties.headers['vadara']['provider']

          puts " [vadara][scaler] reply = " + payload

          reply = JSON.parse(payload)
          reply['new_instances'].each do |new_instance|
            # new instance
            @instances[provider] << {
              instance_id: new_instance['instance_id'],
              launch_time: Time.at(new_instance['launch_time'])
            }
            # write into DB
            @db.write_point(instances_series,
              provider: provider,
              instance_id: new_instance['instance_id'],
              launch_time: new_instance['launch_time']
            )

            # new bootup time
            @bootup_times[provider] << new_instance['bootup_time']
            # write into DB
            @db.write_point(bootup_times_series,
              provider: provider,
              bootup_time: new_instance['bootup_time'],
            )
          end
        end
      end

      def load_db_info
        instances_series = @config[:db][:instances_series]
        bootup_times_series = @config[:db][:bootup_times_series]

        @config[:cps].each do |provider,info|
          next unless info[:active]

          provider = provider.to_s

          # load instances for all active
          @instances[provider] = Array.new

          @db.query "SELECT instance_id, launch_time FROM #{instances_series} WHERE provider = '#{provider}'" do |name,points|
            points.each do |point|
              instance_id = point['instance_id']
              launch_time = Time.at point['launch_time']

              @instances[provider] << { instance_id: instance_id, launch_time: launch_time }
            end
          end

          # load providers bootup time
          @bootup_times[provider] = Array.new

          @db.query "SELECT bootup_time FROM #{bootup_times_series} WHERE provider = '#{provider}'" do |name,points|
            points.each do |point|
              @bootup_times[provider] << point['bootup_time']
            end
          end
        end
      end
  end
end
