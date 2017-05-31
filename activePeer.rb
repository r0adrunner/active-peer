#!/usr/bin/env ruby
# coding: utf-8
BEGIN {$VERBOSE = true}

require "socket"
require 'optparse'

BUFFER_SIZE = 1024 * 2

# Parameters parsing ===================================================================

$parameters = {}
opt_parser = OptionParser.new do |opts|
  opts.banner = "Usage: activePeer.rb <ACTIVE|PASSIVE> [options]"

  opts.on('-tp', '--tunnelPort PORT', 'Port of the tunnel connection') { |v| $parameters[:tun_port] = v.to_i }

  opts.on('-ta', '--tunnelAddr ADDR', 'Address of the tunnel connection') { |v| $parameters[:tun_addr] = v }

  opts.on('-ap', '--appPort PORT', 'Port of the connection to the application') { |v| $parameters[:app_port] = v.to_i }

  opts.on('-aa', '--appAddr ADDR', 'Address of the connection to the application') { |v| $parameters[:app_addr] = v }

  opts.on('-ti', '--tunnelInterval INTERVAL', 'Interval in seconds to wait between tunnel connection attempts. If this value is zero, try to connect only once and quit on fail. Default = 0') { |v| $parameters[:tun_interval] = v.to_i }

  opts.on('-ai', '--appInterval INTERVAL', 'Interval in seconds to wait between app connection attempts. If this value is zero, try to connect only once and quit on fail. Default = 0') { |v| $parameters[:app_interval] = v.to_i }

  opts.on('-r', '--reestablish', 'Restablish tunnel connection again if it breaks') { |v| $parameters[:reestablish] = v }

  opts.on('-h', '--help', 'Prints this help') { puts opts }

end

if !ARGV[0] || $parameters[:help]
  opt_parser.parse %w[--help]
  exit
end
opt_parser.parse!

# Defaults

if !$parameters.key?(:app_addr)
  $parameters[:app_addr] = "127.0.0.1"
end

if !$parameters.key?(:tun_addr)
  $parameters[:tun_addr] = "127.0.0.1"
end

if !$parameters.key?(:tun_interval)
  $parameters[:tun_interval] = 0
end

# Todo: bad code
if $parameters[:reestablish] && ($parameters[:tun_interval] < 1)
  $parameters[:tun_interval] = 1
end

if !$parameters.key?(:app_interval)
  $parameters[:app_interval] = 0
end

# Sockets ===================================================================

class Client

  def connect( port, addr )
    @server = nil
    @server = TCPSocket.open( addr, port )
    @serverinfo = @server.addr.inspect + " Remote port: " + port.to_s
    puts "Connected:"
    puts @serverinfo
  end

  def listen
    loop {
      begin
        if @server.eof?
          print(@serverinfo, " is gone\n")
          close
          break
        else 
          msg = @server.readpartial(BUFFER_SIZE)
          yield (msg)
        end
      rescue IOError, Interrupt
        close        
        print(@serverinfo, " closed\n")
        break
      end
    }
  end

  def is_closed?
    @server == nil
  end

  def close
    return if is_closed?
    @server.close
    @server = nil
  end
  
  def send (data)
    if is_closed? then abort ("Attempt to send data to a closed socket. Exiting") end
    @server.write data
    @server.flush
  end
  
end

class Server

  @on_accept = nil

  def connect( port, addr , &onaccept)
    @server = nil
    @client = nil
    @on_accept = onaccept

    @server = TCPServer.open( addr, port )
    @serverinfo = @server.addr.inspect
    puts " socket created"
    puts @serverinfo
  end

  def accept
    begin
      @client = @server.accept
    rescue Interrupt
      puts("Interrupt")
      exit
    end

    if @on_accept != nil
      @on_accept.call
    end

  end

  def listen
    accept
    @clientinfo = @client.addr.inspect
    puts "Accepted:"
    puts @clientinfo
    loop {
      begin
        if @client.eof?
          print(@clientinfo, " is gone\n")
          close
          break
        else 
          msg = @client.readpartial (BUFFER_SIZE)
          yield (msg)
        end
      rescue IOError, Interrupt
        print(@clientinfo, " closed\n")
        break
      end
      
    }
  end

  def is_closed?
    @server == nil || @client == nil
  end

  def close
    @client.close if @client != nil
    @server.close if @server != nil    
    @client = nil
    @server = nil
  end

  def send (data)
    if is_closed? then abort ("Attempt to send data to a closed socket. Exiting") end
    @client.write data
    @client.flush
  end

  # end class server
end

# =======================================================================================

class SocketController

  @tunSock = nil
  @appSock = nil
  @didIHangup = false

  def try_connect (interval)
    # interval should be tunnel interval. if zero, try only once
    if interval != 0
      loop {
        begin
          yield
          return true
        rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::EINPROGRESS
        rescue Errno::EISCONN
          return false
        end

        begin
          sleep interval
        rescue Interrupt
          puts("Interrupt")
          exit
        end
      }
    else
    # if interval = zero, try only once      
      begin 
        yield
        return true
      rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::EINPROGRESS, Errno::EISCONN
        return false
      end
    end
  end

  def listen_tun_socket ()
    @tunSock.listen do |data|
      if @appSock == nil
        abort ("Trying to send data to a closed app socket. Exiting")
      end
      @appSock.send data
    end
  end

  def listen_app_socket ()
    @appSock.listen do |data|
      if @tunSock == nil
        abort ("Trying to send data to a closed tunnel socket. Exiting")
      end
      @tunSock.send data
    end
  end

  def do_tunnel_server (&on_accept)
    @tunSock = Server.new
    @tunSock.connect($parameters[:tun_port], $parameters[:tun_addr]) do
      on_accept.call
    end
    listen_tun_socket
    tun_socket_on_terminate
  end

  def do_app_server
    @appSock = Server.new
    @appSock.connect($parameters[:app_port], $parameters[:app_addr]) {}
    listen_app_socket
    app_socket_on_terminate
  end

  def do_tunnel_client (&on_connect)
    @tunSock = Client.new
    if try_connect ($parameters[:tun_interval]) {@tunSock.connect($parameters[:tun_port], $parameters[:tun_addr])}
      on_connect.call
      listen_tun_socket
    end
    tun_socket_on_terminate
  end

  def do_app_client
    @appSock = Client.new
    if try_connect ($parameters[:app_interval]) {@appSock.connect($parameters[:app_port], $parameters[:app_addr])}
      listen_app_socket
    end
    app_socket_on_terminate
  end

  def app_socket_on_terminate
    if !@didIHangup
      puts "Closing tunnel connection"
      @didIHangup = true       
      if @tunSock != nil
        @tunSock.close
      end
    else
      @didIHangup = false
    end
  end

  def tun_socket_on_terminate
    if !@didIHangup
      puts "Closing app connection"
      @didIHangup = true                
      if @appSock != nil
        @appSock.close
      end
    else
      @didIHangup = false
    end
  end

  def reestablishing
    loop {
      yield
      if !$parameters[:reestablish]
        puts "Won't reestablish connections"
        break
      else
        puts "Reestablishing connection..."
      end
    }
  end

  def start (mode)

    if mode == :active
      reestablishing do
        do_tunnel_client do
          # on connect:
          Thread.new do
            sleep 0.1
            do_app_client
          end
        end
      end
    elsif mode == :passive
      reestablishing do
        do_tunnel_server do
          # on accept:
          Thread.new do
            sleep 0.1
            do_app_server
          end
        end
      end
    end

  end

  # end class socketcontroller
end

# Main =================================================================================

if ARGV[0].downcase == 'active'
  puts "Starting in active mode..."
  SocketController.new.start (:active)

elsif ARGV[0].downcase == 'passive'
  puts "Starting in passive mode..."
  SocketController.new.start (:passive)

end
