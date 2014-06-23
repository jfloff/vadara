require 'yaml'
require 'json'
require 'aws-sdk-core'
require 'require_all'
require 'bunny'
require_rel 'monitor_request.rb'

module AwsVadara
  class Monitor

    def initialize(ids)
      @ids = ids
      @config = YAML.load_file(File.dirname(__FILE__) + '/aws.yml')

      Aws.config = {
        access_key_id: @config['access_key_id'],
        secret_access_key: @config['secret_access_key'],
        region: @config['region']
      }

      @cw = Aws::CloudWatch.new
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
        case request.metric_name
          when 'cpu_usage'
            reply_to_cpu_usage(request.statistics, request.start_time, request.end_time, request.period, request.detail)
          when 'request_count'
            reply_to_request_count(request.start_time, request.end_time, request.period)
        end
      end

      def reply_to_request_count(start_time, end_time, period)
        options = {
          # http://docs.aws.amazon.com/AmazonCloudWatch/latest/DeveloperGuide/aws-namespaces.html
          namespace: 'AWS/ELB',
          # http://docs.aws.amazon.com/AmazonCloudWatch/latest/DeveloperGuide/elb-metricscollected.html
          metric_name: 'RequestCount',
          statistics: ['Sum', 'Maximum', 'Minimum', 'SampleCount', 'Average'],
          start_time: start_time,
          end_time: end_time,
          period: period,
          dimensions: [{
            name: "LoadBalancerName",
            value: @config['load_balancer']['name']
          }]
        }

        # http://docs.aws.amazon.com/AmazonCloudWatch/latest/APIReference/API_GetMetricStatistics.html
        result = @cw.get_metric_statistics(options)

        reply = Array.new
        result[:datapoints].each do |datapoint|
          reply << datapoint.to_h
        end

        return reply
      end

      def reply_to_cpu_usage(statistics, start_time, end_time, period, detail)

        options = {
          # http://docs.aws.amazon.com/AmazonCloudWatch/latest/DeveloperGuide/aws-namespaces.html
          namespace: "AWS/EC2",
          # http://docs.aws.amazon.com/AmazonCloudWatch/latest/DeveloperGuide/ec2-metricscollected.html
          metric_name: 'CPUUtilization',
          # metrics in API are uppercase
          statistics: statistics.map(&:capitalize),
          start_time: start_time,
          end_time: end_time,
          period: period,
          dimensions: '' # placeholder
        }

        case detail
        when 'detailed'
          all_datapoints = Hash.new
          @ids.each do |id|
            options[:dimensions] =  [{ name: "InstanceId", value: id }]

            result = @cw.get_metric_statistics(options)
            result[:datapoints].each do |datapoint|
              timestamp = datapoint['timestamp']

              all_datapoints[timestamp] = Hash.new unless all_datapoints.has_key? timestamp

              statistics.each do |statistic|
                all_datapoints[timestamp][statistic] = Array.new unless all_datapoints[timestamp].has_key? statistic
                all_datapoints[timestamp][statistic] << datapoint[statistic]
              end
            end
          end

          reply = Hash.new
          all_datapoints.each do |timestamp, statistics|
            reply[timestamp] = Hash.new

            if statistics.has_key? 'min'
              reply[timestamp]['min'] = statistics['min'].min
            end
            if statistics.has_key? 'max'
              reply[timestamp]['max'] = statistics['max'].max
            end
            if statistics.has_key? 'average'
              reply[timestamp]['avg'] = statistics['average'].inject{ |sum, el| sum + el }.to_f / statistics['average'].size
            end
          end

          return reply
        when 'condensed'
          all_datapoints = Hash.new
          @ids.each do |id|
            options[:dimensions] =  [{ name: "InstanceId", value: id }]

            result = @cw.get_metric_statistics(options)
            result[:datapoints].each do |datapoint|
              statistics.each do |statistic|
                all_datapoints[statistic] = Array.new unless all_datapoints.has_key? statistic
                all_datapoints[statistic] << datapoint[statistic]
              end
            end
          end

          reply = Hash.new
          if all_datapoints.has_key? 'min'
            reply['min'] = all_datapoints['min'].min
          end
          if all_datapoints.has_key? 'max'
            reply['max'] = all_datapoints['max'].max
          end
          if all_datapoints.has_key? 'average'
            reply['avg'] = all_datapoints['average'].inject{ |sum, el| sum + el }.to_f / all_datapoints['average'].size
          end

          return reply
        end
      end
  end
end
