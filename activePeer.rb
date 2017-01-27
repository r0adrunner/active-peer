#!/usr/bin/env ruby
# coding: utf-8
BEGIN {$VERBOSE = true}

require "socket"
require 'optparse'

BUFFER_SIZE = 1024 * 2
DEFAULT_IN_INTERVAL = 5            # Seconds
DEFAULT_OUT_INTERVAL = 5            # Seconds

# Parameters parsing ===================================================================

$parameters = {}
opt_parser = OptionParser.new do |opts|
  opts.banner = "Usage: activePeer.rb <ACTIVE|PASSIVE> [options]"

  opts.on('-ip', '--inPort PORT', 'Port of the inbound straw') { |v| $parameters[:in_port] = v.to_i }

  opts.on('-ia', '--inAddr ADDR', 'Address of the inbound straw') { |v| $parameters[:in_addr] = v }

  opts.on('-op', '--outPort PORT', 'Port of the outbound straw') { |v| $parameters[:out_port] = v.to_i }

  opts.on('-oa', '--outAddr ADDR', 'Address of the outbound straw') { |v| $parameters[:out_addr] = v }

  opts.on('-a', '--aggressive', 'Attempt to establish the connection repeatedly (only for active mode)') { |v| $parameters[:aggressive] = v }

  opts.on('-ii', '--inInterval INTERVAL', 'Interval used for aggressive inbound straw connection attempt') { |v| $parameters[:in_interval] = v.to_i }

  opts.on('-oi', '--outInterval INTERVAL', 'Interval used for aggressive outbound straw connection attempt') { |v| $parameters[:out_interval] = v.to_i }

  # Todo:
  # opts.on('-e', '--resilient', 'Do not drop other straw if one breaks.) { |v| $parameters[:resilient] = v }

  opts.on('-r', '--reestablish', 'Try connecting again after the connection was broken') { |v| $parameters[:reestablish] = v }

  opts.on('-h', '--help', 'Prints this help') { puts opts }

end

if !ARGV[0] || $parameters[:help]
  opt_parser.parse %w[--help]
  exit
end
opt_parser.parse!

# Defaults

if !$parameters.key?(:in_addr)
  $parameters[:in_addr] = "127.0.0.1"
end

if !$parameters.key?(:out_addr)
  $parameters[:out_addr] = "127.0.0.1"
end

if !$parameters.key?(:out_interval)
  $parameters[:out_interval] = DEFAULT_OUT_INTERVAL
end

if !$parameters.key?(:in_interval)
  $parameters[:in_interval] = DEFAULT_IN_INTERVAL
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

  def connect( port, addr )
    @server = nil
    @client = nil

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

end

# =======================================================================================

class SocketController

  @inSock = nil
  @outSock = nil

  def try_connect (interval)
    if $parameters[:aggressive]
      loop {
        begin
          yield
          return
        rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::EINPROGRESS
        rescue Errno::EISCONN
          return
        end

        begin
          sleep interval
        rescue Interrupt
          puts("Interrupt")
          exit
        end
      }
    else
      yield
    end
  end

  def listen_socket_i ()
    @inSock.listen do |data|
      if @outSock == nil
        abort ("Trying to send data to a closed socket. Exiting")
      end
      @outSock.send data
    end
  end

  def listen_socket_o ()
    @outSock.listen do |data|
      if @inSock == nil
        abort ("Trying to send data to a closed socket. Exiting")
      end
      @inSock.send data
    end
  end

  def do_socket_ip
      @inSock = Server.new
      @inSock.connect($parameters[:in_port], $parameters[:in_addr])
      listen_socket_i
      socket_on_terminate_i
  end

  def do_socket_op
      @outSock = Server.new
      @outSock.connect($parameters[:out_port], $parameters[:out_addr])
      listen_socket_o
      socket_on_terminate_o
  end

  def do_socket_ia
      @inSock = Client.new
      try_connect ($parameters[:in_interval]) {@inSock.connect($parameters[:in_port], $parameters[:in_addr])}
      listen_socket_i
      socket_on_terminate_i
  end

  def do_socket_oa
      @outSock = Client.new
      try_connect ($parameters[:out_interval]) {@outSock.connect($parameters[:out_port], $parameters[:out_addr])}
      listen_socket_o
      socket_on_terminate_o
  end

  def socket_on_terminate_i
    # Todo: avoid closing connections reciprocally

    # if !$parameters[:resilient]
    #   puts "Closing outb. connection because resilient == false"
    #   @outSock.close
    # end
  end

  def socket_on_terminate_o
    # Todo: avoid closing connections reciprocally

    # if !$parameters[:resilient]
    #   puts "Closing inb. connection because resilient == false"
    #   @inSock.close
    # end
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

      threads = []

      # Start inbound socket
      threads << Thread.new do
        reestablishing do
          if mode == :active
            do_socket_ia
          elsif mode == :passive
            do_socket_ip
          end
        end
      end

      sleep 0.1

      # Start outbound socket
      threads << Thread.new do
        reestablishing do
          if mode == :active
            do_socket_oa
          elsif mode == :passive
            do_socket_op
          end
        end
      end

      threads.each { |thr| thr.join }

  end

end

# Main =================================================================================

if ARGV[0].downcase == 'active'
  puts "Starting in active mode..."
  SocketController.new.start (:active)

elsif ARGV[0].downcase == 'passive'
  puts "Starting in passive mode..."
  SocketController.new.start (:passive)

end
