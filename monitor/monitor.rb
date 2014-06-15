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
      begin
        Thread.new { reply_to_decider }
        receive_from_decider
      rescue Interrupt => _
        @conn.close
        puts " [vadara][monitor] Closing connection"
        exit(0)
      end
    end

    private

      def receive_from_decider
        monitor_channel = @conn.create_channel
        monitor_queue = monitor_channel.queue(@config[:queues][:monitor][:request])

        providers_channel = @conn.create_channel
        providers_channel_fanout = providers_channel.fanout(@config[:queues][:monitor][:fanout])

        puts " [vadara][monitor] Waiting `decider` messages"
        monitor_queue.subscribe(:block => true) do |delivery_info, properties, body|
          request = MonitorRequest.new JSON.parse(body)

          providers_channel_fanout.publish(request.to_json)
          puts " [vadara][monitor] Sent CP request"
          # puts " [vadara][monitor] " + request.to_json
        end
      end

      def reply_to_decider
        providers_channel = @conn.create_channel
        providers_reply_queue = providers_channel.queue(@config[:queues][:monitor][:reply])

        puts " [vadara][monitor] Waiting CPs replies"
        providers_reply_queue.subscribe(:block => true) do |delivery_info, properties, body|
          request = JSON.parse(body)

          puts " [vadara][monitor] Received CP reply"
          # puts " [vadara][monitor] " + request.to_json

          # aggregate requests from CPs??
        end
      end
  end
end
