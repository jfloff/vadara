require 'yaml'
require 'json'
require 'aws-sdk-core'
require 'require_all'
require 'bunny'
require_rel 'monitor_request.rb'

module AwsVadara
  class Monitor

    def initialize(ids)
      @config = YAML.load_file(File.dirname(__FILE__) + '/aws.yml')

      Aws.config = {
        access_key_id: @config['access_key_id'],
        secret_access_key: @config['secret_access_key'],
        region: @config['region']
      }

      @instances_ids = Array.new
      ids.each do |id|
        @instances_ids << {
          name: "InstanceId",
          value: id
        }
      end
    end

    def run(request_queue_name, reply_queue_name, fanout)

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
        puts " [aws][monitor] Waiting for messages"
        provider_queue.subscribe(:block => true) do |delivery_info, properties, body|
          # request
          request = request(body)
          puts " [aws][monitor] Received request"

          # reply to queue
          reply = JSON.generate(reply(request))
          # puts " [aws][monitor] " + reply

          # send reply to queue
          channel.default_exchange.publish(reply, routing_key: reply_queue.name)
          puts " [aws][monitor] Sent reply!"
        end
      rescue Interrupt => _
        puts "[aws][monitor] Closing connection."
        conn.close
        exit
      end
    end

    # private
      def request(body)
        # Monitor request from JSON
        return MonitorRequest.new JSON.parse(body)
      end

      def reply(request)

        # cloud watch instance
        cw = Aws::CloudWatch.new

        if (request.metric_name == 'RequestCount')
          namespace = "AWS/ELB"
          dimensions = [{
            name: "LoadBalancerName",
            value: @config[:cps][:aws][:load_balancer][:name]
          }]
        else
          namespace = "AWS/EC2"
          dimensions = @instances_ids
        end

        options = {
          # http://docs.aws.amazon.com/AmazonCloudWatch/latest/DeveloperGuide/aws-namespaces.html
          namespace: namespace,
          metric_name: request.metric_name,
          statistics: request.statistics,
          start_time: request.start_time,
          end_time: request.end_time,
          period: request.period,
          dimensions: dimensions
        }

        result = cw.get_metric_statistics(options)

        datapoints_array = Array.new
        result[:datapoints].each do |datapoint|
          datapoints_array << datapoint.to_h
        end

        return datapoints_array
      end

  end
end
