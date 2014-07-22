require 'bunny'
require 'json'
require 'require_all'
require 'thread'
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

      @instances_to_delete = Hash.new
      @lock = Mutex.new

      @sort_full_hour_block = Proc.new { |x, y|
        now = Time.now

        # 60 modulo of the minutes different gives in the rest the number of minutes
        # since the new hour begun --> the more minutes, the closer it is
        diff1 = ((now - x[:launch_time]) / 60) % 60
        diff2 = ((now - y[:launch_time]) / 60) % 60

        # smallest different first
        diff2 <=> diff1
      }

      # init for all active CPs
      @config[:cps].each do |provider,info|
        next unless info[:active]
        provider = provider.to_s

        @instances[provider] = Array.new
        @bootup_times[provider] = Array.new
        @instances_to_delete[provider] = Array.new
      end

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
        run_hour_scale_down_thread(providers_channel_fanout)

        puts " [vadara][scaler] Waiting `decider` messages"
        scaler_queue.subscribe(:block => true) do |delivery_info, properties, payload|
          request = ScalerRequest.new JSON.parse(payload)

          request.horizontal_scale_down = instances_to_scale_down(request.horizontal_scale_down)

          providers_channel_fanout.publish(request.to_json)

          puts " [vadara][scaler] Sent CP request"
          puts " [vadara][scaler] request = " + request.to_json
        end
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

        @instances.each do |provider,info|

          @db.query "SELECT instance_id, launch_time FROM #{instances_series} WHERE provider = '#{provider}'" do |name,points|
            points.each do |point|
              instance_id = point['instance_id']
              launch_time = Time.at point['launch_time']

              @instances[provider] << { instance_id: instance_id, launch_time: launch_time }
            end
          end

          @db.query "SELECT bootup_time FROM #{bootup_times_series} WHERE provider = '#{provider}'" do |name,points|
            points.each do |point|
              @bootup_times[provider] << point['bootup_time']
            end
          end
        end
      end

      ########################################################################################
      ###################################### SCALE DOWN ######################################
      ########################################################################################

      def instances_to_scale_down(request_scale_down)
        to_delete = Hash.new
        request_scale_down.each do |provider, n|

          if @config[:cps][provider.to_sym][:full_period_unit] == 'h'
            to_delete[provider] = hour_scale_down(provider, n)
          else
            to_delete[provider] = min_sec_scale_down(provider, n)
          end

        end
        return to_delete
      end

      def hour_scale_down(provider, n)

        instances = @instances[provider].sort(&@sort_full_hour_block)

        instances.shift(n).each do |instance|
          @lock.synchronize {
            @instances_to_delete[provider] << instance[:instance_id]
          }
        end
      end

      def run_hour_scale_down_thread(fanout)
        instances_near_full_hour = Hash.new
        @lock.synchronize {
          @instances_to_delete.each do |provider, instances_to_delete|
            # select instances that are above 55mins left in the
            instances = instances_to_delete.select { |x| x >= 55 }

            unless instances.empty?
              instances_near_full_hour[provider] = instances
            end
          end
        }

        # if there are any instances near full hour sends order to terminate them
        # removes them from its queue
        unless instances_near_full_hour.empty?
          request = ScalerRequest.new
          request.horizontal_scale_down =
          fanout.publish(request.to_json)
        end

        max = 0
        @instances.each do |provider, instances|
          instance_max = instances.sort(&@sort_full_hour_block).max

          max = instance_max > max ? instance_max : max
        end

        sleep(50 - max)
      end

      def min_sec_scale_down(provider, n)
        # sort instances by time
        instances = @instances[provider].sort  { |x, y| x[:launch_time] <=> y[:launch_time] }
        to_delete = Array.new
        instances.shift(n).each do |instance|
          to_delete << instance[:instance_id]
        end
        return to_delete
      end
  end
end
