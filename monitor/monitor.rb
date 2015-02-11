 require 'bunny'
require 'json'
require 'require_all'
require_rel 'monitor_request.rb'

module Vadara
  class Monitor

    def initialize(config)
      @config = config

      @conn = Bunny.new(automatically_recover: false)
      @conn.start
    end

    def run
      return Thread.new{
        begin
          reply_t = Thread.new { reply_to_decider }
          receive_t = Thread.new { receive_from_decider }

          reply_t.join
          receive_t.join

        rescue Interrupt => _
          @conn.close
          puts " [vadara][monitor] Closing connection"
          Thread.exit
        end
      }
    end

    private

      def receive_from_decider
        monitor_channel = @conn.create_channel
        monitor_queue = monitor_channel.queue(@config[:queues][:monitor][:request])

        providers_channel = @conn.create_channel
        providers_channel_fanout = providers_channel.fanout(@config[:queues][:monitor][:fanout])

        puts " [vadara][monitor] Waiting `decider` messages"
        monitor_queue.subscribe(:block => true) do |delivery_info, properties, payload|
          request = decider_request_to_providers(payload)

          providers_channel_fanout.publish(request)
          puts " [vadara][monitor] Sent CP request"
          puts " [vadara][monitor] request = " + payload
        end
      end

      def decider_request_to_providers(payload)
        return payload
      end

      def reply_to_decider
        providers_channel = @conn.create_channel
        providers_reply_queue = providers_channel.queue(@config[:queues][:monitor][:reply])

        decider_reply_channel = @conn.create_channel
        decider_queue = decider_reply_channel.default_exchange

        puts " [vadara][monitor] Waiting CPs replies"
        providers_reply_queue.subscribe(:block => true) do |delivery_info, properties, payload|
          reply = providers_reply_to_decider(payload)

          puts " [vadara][monitor] Received CP reply"
          puts " [vadara][monitor] reply = " + reply

          decider_queue.publish(reply, routing_key: @config[:queues][:decider][:reply])
        end
      end

      def providers_reply_to_decider(payload)
        return payload
      end
  end
end
