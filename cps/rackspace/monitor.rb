require 'yaml'
require 'json'
require 'bunny'
require 'fog'
require 'require_all'
require 'thread'
require 'active_support/core_ext/time'
require_rel 'monitor_request.rb'

module RackspaceVadara
  class Monitor

    def initialize(entities,lock)
      @config = YAML.load_file(File.dirname(__FILE__) + '/rackspace.yml')

      options = {
        rackspace_username: @config['username'],
        rackspace_api_key: @config['api_key'],
        rackspace_auth_url: @config['auth_url'],
        rackspace_region: @config['region'].downcase.to_sym,
      }
      @monitoring = Fog::Rackspace::Monitoring.new(options)
      @load_balancers = Fog::Rackspace::LoadBalancers.new(options)

      @entities = entities
      @lock = lock
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
          puts " [rackspace][monitor] Waiting for messages"
          provider_queue.subscribe(:block => true) do |delivery_info, properties, body|

            # request
            request = request(body)
            puts " [rackspace][monitor] Received request"

            # reply to queue
            reply = JSON.generate(reply(request))

            # send reply to queue
            channel.default_exchange.publish(reply,
              headers: { vadara: { provider: 'rackspace' } },
              routing_key: reply_queue.name)
            puts " [rackspace][monitor] Sent reply!"
          end
        rescue Interrupt => _
          puts "[rackspace][monitor] Closing connection."
          conn.close
          Thread.exit
        end
      }
    end

    private
      def request(body)
        # Monitor request from JSON
        return MonitorRequest.new JSON.parse(body)
      end

      def reply(request)

        case request.metric_name
          when 'cpu_usage'
            reply_to_cpu_usage(request.statistics, request.start_time, request.end_time, request.period, request.detail)
          when 'request_count'
            reply_to_request_count()
        end
      end

      def reply_to_request_count()
        reply = Hash.new
        # atm not possible to know the total of requests of a lb
        reply[:total_requests] = 'NA'

        id = @config['load_balancer']['id']

        # http://docs.rackspace.com/loadbalancers/api/v1.0/clb-devguide/content/API_Operations-d1e1354.html
        # usage = @load_balancers.get_load_balancer_usage(id)
        current_conn = @load_balancers.get_stats(id).body['currentConn']
        reply[:current_requests] = current_conn

        return reply
      end

      def reply_to_cpu_usage(statistics, start_time, end_time, period, detail)
        # time has to be in miliseconds
        start_time = (start_time.to_f * 1000).to_i
        end_time = (end_time.to_f * 1000).to_i

        # period comes in seconds, we have to find out how many points
        # that period translates to for rackspace API
        # http://docs.rackspace.com/cm/api/v1.0/cm-devguide/content/metrics-api.html#metrics-api-summary
        points = (end_time - start_time) / (period * 1000)

        case detail
          when 'condensed'
            all_points = Hash.new

            @lock.synchronize {
              @entities.each do |entity_id, info|
                # skips if entity doesn't has a cpu_check_id
                next unless info.has_key? :cpu_check_id

                opts = { from: start_time, to: end_time, points: points, select: statistics }
                data_points = @monitoring.list_data_points(entity_id, info[:cpu_check_id], 'usage_average', opts).body.values[0]

                data_points.each do |data_point|
                  data_point.each do |statistic,value|
                    all_points[statistic] = Array.new unless all_points.has_key? statistic

                    # merges statistics with previous ones from other entities
                    all_points[statistic] << value
                  end
                end
              end
            }

            reply = Hash.new
            if all_points.has_key? 'min'
              reply['min'] = all_points['min'].min
            end
            if all_points.has_key? 'max'
              reply['max'] = all_points['max'].max
            end
            if all_points.has_key? 'average'
              reply['avg'] = all_points['average'].inject{ |sum, el| sum + el }.to_f / all_points['average'].size
            end

            return reply
          when 'detailed'
            all_points = Hash.new

            @lock.synchronize {
              @entities.each do |entity_id, info|
                # skips if entity doesn't has a cpu_check_id
                next unless info.has_key? :cpu_check_id

                opts = { from: start_time, to: end_time, points: points, select: statistics }
                data_points = @monitoring.list_data_points(entity_id, info[:cpu_check_id], 'usage_average', opts).body.values[0]

                data_points.each do |data_point|
                  # remove miliseconds so we match more efficiently with other entities
                  timestamp = Time.at(data_point.delete('timestamp')/1000).change(sec: 0).to_i

                  #checks if its the fist timestamp
                  all_points[timestamp] = Hash.new unless all_points.has_key? timestamp

                  data_point.each do |statistic,value|
                    # inits array for values in case doesn't exist
                    all_points[timestamp][statistic] = Array.new unless all_points[timestamp].has_key? statistic
                    # merges statistics with previous ones from other entities
                    all_points[timestamp][statistic] << value
                  end
                end
              end
            }

            reply = Hash.new
            all_points.each do |timestamp, statistics|
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
        end
      end
  end
end
