#!/usr/bin/env ruby
# encoding: utf-8

require 'influxdb'
require 'yaml'
require 'require_all'
require 'active_support/core_ext/string'
require_all 'monitor' , 'helpers'

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
      monitor = Vadara::Monitor.new @config
      monitor.run

      # run monitor, scaler and active providers monitors/scalers
    end

    # def self.method_missing(name, *arguments)

    #   name = name.to_s.split('_', 2)

    #   if (name[0] == 'run')
    #     classname = 'Vadara::' + name[1].camelize
    #     puts classname
    #     clazz = Object.const_get(classname).new(@config)
    #     clazz.run
    #   else
    #     raise NotImplementedError.new('This method does not exist')
    #   end
    # end

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
        instances_series = @config[:db][:instances_series]
        @db.query 'delete from ' + instances_series

        puts " [vadara][core] `repository` ready!"
      end

      def init_cps
        #reset instances
        @db.query 'DELETE FROM ' + @config[:db][:instances_series]

        @config[:cps].each do |name,info|
          if info[:active]
            puts " [vadara][core] Initiating #{name.to_s} provider"
            init_cp(name, info[:run])
          end
        end
      end

      def init_cp(name, run)
        queue_name = 'vadara.core.' + name.to_s

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
        puts " [vadara][core] Waiting for #{name.to_s} instances"
        q.subscribe(:block => true) do |delivery_info, properties, payload|
          # write instances ids and launch times to db
          db_write_instances(name, JSON.parse(payload))

          puts " [vadara][core] Received #{name.to_s} instances data"

          # answer with opts to init monitor/scaler
          opts = {
            request: @config[:queues][:monitor][:request],
            reply: @config[:queues][:monitor][:reply],
            fanout: @config[:queues][:monitor][:fanout]
          }
          puts " [vadara][core] Sent queues information"
          x.publish(opts.to_json, :routing_key => properties.reply_to)

          ch.close
        end
        conn.close
      end

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
