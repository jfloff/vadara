#!/usr/bin/env ruby
# encoding: utf-8

require 'influxdb'
require 'yaml'
require 'require_all'
require 'active_support/core_ext/string'
require_all 'monitor' , 'helpers', 'scaler'

module Vadara
  module Core
    extend self

    def init
      #init config
      @config = YAML.load_file('config.yml').symbolize_keys

      puts "Welcome to Vadara!\n"
      init_db
      init_cps
      run
    end

    def run
      puts " [vadara][core] Starting services ..."
      monitor = Vadara::Monitor.new @config
      monitor_t = monitor.run

      scaler = Vadara::Scaler.new(@config, @db)
      scaler_t = scaler.run

      begin
        monitor_t.join
        scaler_t.join
      rescue Interrupt => _
        monitor_t.raise Interrupt
        scaler_t.raise Interrupt
      end

      # run monitor, scaler and active providers monitors/scalers
    end

    private

      def init_db
        puts " [vadara][core] Initiating `repository`"

        @db = InfluxDB::Client.new
        database = @config[:db][:name]
        username = @config[:db][:username]
        password = @config[:db][:password]
        time_precision = 's'

        #create database if necessary
        unless(@db.get_database_list.any? {|h| h['name'] == database})
          @db.create_database(database)
        end

        #reset instances series
        @db = InfluxDB::Client.new database, username: username, password: password, time_precision: time_precision
        @db.query 'DELETE FROM ' + @config[:db][:instances_series]

        puts " [vadara][core] `repository` ready!"
      end

      def init_cps
        @config[:cps].each do |name,info|
          if info[:active]
            puts " [vadara][core] Initiating #{name.to_s} provider"
            init_cp(name, info[:run])
          end
        end
      end

      def init_cp(name, run)
        provider = name.to_s

        queue_name = 'vadara.core.' + provider

        # Launch Core
        pid = spawn(run + ' ' + queue_name)
        # Process.detach pid

        # init bunny
        conn = Bunny.new
        conn.start
        ch = conn.create_channel

        # default exchange
        q = ch.queue(queue_name)
        x = ch.default_exchange

        consumer = nil
        puts " [vadara][core] Waiting for #{provider} instances"
        q.subscribe(:block => true) do |delivery_info, properties, payload|
          # write instances ids and launch times to db
          # { instance_id: ID, launch_time: TIME}
          db_write_instances(name, JSON.parse(payload))

          puts " [vadara][core] Received #{provider} instances data"

          # answer with opts to init monitor/scaler
          opts = {
            monitor: {
              request: @config[:queues][:monitor][:request],
              reply: @config[:queues][:monitor][:reply],
              fanout: @config[:queues][:monitor][:fanout]
            },
            scaler: {
              request: @config[:queues][:scaler][:request],
              reply: @config[:queues][:scaler][:reply],
              fanout: @config[:queues][:scaler][:fanout],
              min_bootup_time: min_bootup_time(provider)
            },
          }
          puts " [vadara][core] Sent queues information"
          x.publish(opts.to_json, :routing_key => properties.reply_to)

          ch.close
        end
        conn.close
      end

      def min_bootup_time(provider)
        bootup_times_series = @config[:db][:bootup_times_series]

        times = Array.new
        @db.query "SELECT bootup_time FROM #{bootup_times_series} WHERE provider = '#{provider}'" do |name,points|
          points.each do |point|
            times << point['bootup_time']
          end
        end

        # if no min available returns 1 so we found out
        return times.min.nil? ? 1 : times.min
      end

      # { instance_id:  ..., launch_time: in seconds epoch unix time > }
      def db_write_instances(name, instances)
        series = @config[:db][:instances_series]

        instances.each do |instance|
          instance['provider'] = name
          @db.write_point(series, instance)
        end
      end
  end
end

Vadara::Core.init
# Vadara::Core.send(ARGV[0])
