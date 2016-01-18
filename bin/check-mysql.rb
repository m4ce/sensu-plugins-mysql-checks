#!/usr/bin/env ruby
#
# check-mysql.rb
#
# Author: Matteo Cerutti <matteo.cerutti@hotmail.co.uk>
#

require 'sensu-plugin/check/cli'
require 'mysql2'
require 'json'

class CheckMySQL < Sensu::Plugin::Check::CLI
  option :host,
         :description => "MySQL host (default: localhost)",
         :short => "-H <HOST>",
         :long => "--host <HOST>",
         :default => "localhost"

  option :port,
         :description => "MySQL port (default: 3306)",
         :short => "-p <PORT>",
         :long => "--port <PORT>",
         :proc => proc(&:to_i),
         :default => 3306

  option :username,
         :description => "MySQL user",
         :short => "-u <USER>",
         :long => "--user <USER>",
         :default => nil

  option :password,
         :description => "MySQL password",
         :long => "--password <PASSWORD>",
         :default => nil

  option :config_file,
         :description => "Optional configuration file (default: #{File.dirname(__FILE__)}/mysql.json)",
         :short => "-c <PATH>",
         :long => "--config <PATH>",
         :default => File.dirname(__FILE__) + "/mysql.json"

  option :uptime,
         :description => "Uptime in seconds",
         :long => "--uptime <UPTIME>",
         :proc => proc(&:to_i),
         :default => 300

  option :warn_conn,
         :description => "Warn if PERCENTAGE exceeds the current number of open connections in relation to max connections (default: 80)",
         :long => "--warn-conn <PERCENTAGE>",
         :proc => proc(&:to_i),
         :default => 80

  option :crit_conn,
         :description => "Critical if PERCENTAGE exceeds the current number of open connections in relation to max connections (default: 90)",
         :long => "--crit-conn <PERCENTAGE>",
         :proc => proc(&:to_i),
         :default => 90

  option :warn_slave_lag,
         :description => "Warn if SECONDS exceeds the current slave replication lag (default: 60)",
         :long => "--warn-slave-lag <SECONDS>",
         :proc => proc(&:to_i),
         :default => 60

  option :crit_slave_lag,
         :description => "Critical if SECONDS exceeds the current slave replication lag (default: 120)",
         :long => "--crit-slave-lag <SECONDS>",
         :proc => proc(&:to_i),
         :default => 120

  option :handlers,
         :description => "Comma separated list of handlers",
         :long => "--handlers <HANDLER>",
         :proc => proc { |s| s.split(',') },
         :default => []

  option :dryrun,
         :description => "Do not send events to sensu client socket",
         :long => "--dryrun",
         :boolean => true,
         :default => false

  def initialize()
    super

    if File.exists?(config[:config_file])
      config.merge!(JSON.parse(File.read(config[:config_file]), :symbolize_names => true))
    end

    raise "MySQL user is required" if config[:username].nil?
    raise "MySQL password is required" if config[:password].nil?

    begin
      @client = Mysql2::Client.new(:host => config[:host], :port => config[:port], :username => config[:username], :password => config[:password])
    rescue
      critical("MySQL server is down (#{$!})")
    end
  end

  def send_client_socket(data)
    if config[:dryrun]
      puts data.inspect
    else
      sock = UDPSocket.new
      sock.send(data + "\n", 0, "127.0.0.1", 3030)
    end
  end

  def send_ok(check_name, msg)
    event = {"name" => check_name, "status" => 0, "output" => "#{self.class.name} OK: #{msg}", "handlers" => config[:handlers]}
    send_client_socket(event.to_json)
  end

  def send_warning(check_name, msg)
    event = {"name" => check_name, "status" => 1, "output" => "#{self.class.name} WARNING: #{msg}", "handlers" => config[:handlers]}
    send_client_socket(event.to_json)
  end

  def send_critical(check_name, msg)
    event = {"name" => check_name, "status" => 2, "output" => "#{self.class.name} CRITICAL: #{msg}", "handlers" => config[:handlers]}
    send_client_socket(event.to_json)
  end

  def send_unknown(check_name, msg)
    event = {"name" => check_name, "status" => 3, "output" => "#{self.class.name} UNKNOWN: #{msg}", "handlers" => config[:handlers]}
    send_client_socket(event.to_json)
  end

  def get_uptime()
    res = @client.query("SHOW GLOBAL STATUS LIKE 'Uptime'")
    res.first['Value'].to_i
  end

  def get_threads_connected()
    res = @client.query("SHOW GLOBAL STATUS LIKE 'Threads_connected'")
    res.first['Value'].to_i
  end

  def get_max_connections_setting()
    res = @client.query("SHOW VARIABLES LIKE 'max_connections'")
    res.first['Value'].to_i
  end

  def get_max_used_connections()
    res = @client.query("SHOW GLOBAL STATUS LIKE 'Max_used_connections'")
    res.first['Value'].to_i
  end

  def get_slave_status()
    res = @client.query("SHOW SLAVE STATUS")
    res.first
  end

  def run
    check_name = "mysql-active_connections"
    threads_connected = get_threads_connected()
    max_connections = get_max_connections_setting()
    if threads_connected >= config[:crit_conn] * max_connections / 100
      send_critical(check_name, "Too many active connections - Current: #{threads_connected} (>= #{config[:crit_conn] * max_connections / 100})")
    elsif threads_connected >= config[:warn_conn] * max_connections / 100
      send_warning(check_name, "High number of active connections - Current: #{threads_connected} (>= #{config[:warn_conn] * max_connections / 100})")
    else
      send_ok(check_name, "#{threads_connected} active connections (< #{config[:warn_conn] * max_connections / 100})")
    end

    check_name = "mysql-max_used_connections"
    max_used = get_max_used_connections() 
    if max_used >= config[:crit_conn] * max_connections / 100
      send_warning(check_name, "MySQL server max used connections reached #{max_used} (>= #{config[:crit_conn] * max_connections / 100})")
    else
      send_ok(check_name, "MySQL server max used connections is #{max_used} (< #{config[:crit_conn] * max_connections / 100})")
    end

    # is replication enabled?
    slave = get_slave_status()
    if slave.has_key?('Slave_IO_Running')
      check_name = "mysql-slave-io_thread"
      if slave['Slave_IO_Running'].downcase != 'yes'
        send_critical(check_name, "MySQL slave IO thread not running (Errno: #{slave['Last_IO_Errno']}, Error: #{slave['Last_IO_Error']})")
      else
        send_ok(check_name, "MySQL slave IO thread is running")
      end
    end

    if slave.has_key?('Slave_SQL_Running')
      check_name = "mysql-slave-sql_thread"
      if slave['Slave_SQL_Running'].downcase != 'yes'
        send_critical(check_name, "MySQL slave SQL thread not running (Errno: #{slave['Last_SQL_Errno']}, Error: #{slave['Last_SQL_Error']})")
      else
        send_ok(check_name, "MySQL slave SQL thread is running")
      end
    end

    if slave.has_key?('Last_Errno')
      check_name = "mysql-slave-last_errno"
      if slave['Last_Errno'] != 0
        send_critical(check_name, "MySQL slave replication has failed with #{slave['Last_errno']} error (#{slave['Last_Error']})")
      else
        send_ok(check_name, "MySQL slave replication has no errors")
      end
    end

    if slave.has_key?('Seconds_Behind_Master')
      check_name = "mysql-slave-lag"
      msg = "MySQL slave replication is #{slave['Seconds_Behind_Master']}s behind master"
      if slave['Seconds_Behind_Master'] >= config[:crit_slave_lag]
        send_critical(check_name, "#{msg} (>= #{config[:crit_slave_lag]}s)")
      elsif slave['Seconds_Behind_Master'] >= config[:warn_slave_lag]
        send_warning(check_name, "#{msg} (>= #{config[:warn_slave_lag]}s)")
      else
        send_ok(check_name, "MySQL slave replication is in sync")
      end
    end

    uptime = get_uptime()
    if uptime <= config[:uptime]
      warning("MySQL server restarted #{uptime}s ago")
    end

    ok("MySQL server is running")
  end
end
