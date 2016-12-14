#!/usr/bin/env ruby
BEGIN {$VERBOSE = true}

require "socket"
require 'optparse'

BUFFER_SIZE = 1024 * 2
DEFAULT_IN_INTERVAL = 5            # Seconds
DEFAULT_OUT_INTERVAL = 5            # Seconds

class Client

  def initialize( port, addr )
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
        print(@serverinfo, " closed\n")
        break
      end
    }
  end

  def send (data)
    @server.write data
    @server.flush
  end
  
  def is_closed?
    @server == :closed
  end

  def close
    return if is_closed?
    @server.close
    @server = :closed
  end
  
end

# =======================================================================================
class Server

  def initialize( port, addr )
    @server = TCPServer.open( addr, port )
    @serverinfo = @server.addr.inspect
    puts "Listening:"
    puts @serverinfo
    @client = nil
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
    @server == :closed
  end

  def close
    return if is_closed?
    @client.close
    @server.close
    @server = :closed
  end

  def send (data)
    @client.write data
    @client.flush
  end

end

# Parameters parsing ===================================================================

$parameters = {}
opt_parser = OptionParser.new do |opts|
  opts.banner = "Usage: activePeer.rb <ACTIVE|PASSIVE> [options]"

  opts.on('-ip', '--inPort PORT', 'Port of the incoming straw') { |v| $parameters[:in_port] = v.to_i }

  opts.on('-ia', '--inAddr ADDR', 'Address of the inbound straw') { |v| $parameters[:in_addr] = v }

  opts.on('-op', '--outPort PORT', 'Port of the outbound straw') { |v| $parameters[:out_port] = v.to_i }

  opts.on('-oa', '--outAddr ADDR', 'Address of the outgoing straw') { |v| $parameters[:out_addr] = v }

  opts.on('-a', '--aggressive', 'Attempt to establish the connection repeatedly (only for active mode)') { |v| $parameters[:aggressive] = v }

  opts.on('-ii', '--inInterval INTERVAL', 'Interval used for aggressive inbound straw connection attempt') { |v| $parameters[:in_interval] = v.to_i }

  opts.on('-oi', '--outInterval INTERVAL', 'Interval used for aggressive outbound straw connection attempt') { |v| $parameters[:out_interval] = v.to_i }

  opts.on('-e', '--resilient', 'Do not drop other straw if one breaks') { |v| $parameters[:resilient] = v }

  opts.on('-r', '--retry', 'Try connecting again after the connection was broken') { |v| $parameters[:retry] = v }

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

# =======================================================================================

def try_connect (interval)
  if $parameters[:aggressive]
    loop {
      begin
        resSock = yield
        return resSock
      rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::EINPROGRESS
      rescue Errno::EISCONN
        return resSock
      end

      begin
        sleep interval
      rescue Interrupt
        puts("Interrupt")
        exit
      end
    }
  else
    return yield
  end
end

def start (mode)
  inSocket = nil
  outSocket = nil
  
  loop {
    # In socket
    if mode == :active
      inSocket = try_connect ($parameters[:in_interval]) { Client.new( $parameters[:in_port], $parameters[:in_addr])}
    elsif mode == :passive
      inSocket = Server.new( $parameters[:in_port], $parameters[:in_addr])
    end
    
    # Out socket in a new thread
    Thread.new {
      if mode == :active
        outSocket = try_connect ($parameters[:out_interval]) { Client.new( $parameters[:out_port], $parameters[:out_addr])}
      elsif mode == :passive
        outSocket = Server.new( $parameters[:out_port], $parameters[:out_addr])
      end

      outSocket.listen do |data|
        inSocket.send data
      end

      if !$parameters[:resilient] && !inSocket.is_closed?
        puts "Outbound straw dropped. Closing the inb. straw, because resilient == false"
        inSocket.close
      end
    }

    inSocket.listen do |data|
      outSocket.send data
    end

    if !$parameters[:resilient] && !outSocket.is_closed?
      puts "Inbound straw dropped. Closing the out straw, because resilient == false"
      outSocket.close
    end

    if !$parameters[:retry]
      puts "Won't retry inbound straw connection"
      break
    end
  }

end

# Main =================================================================================

if ARGV[0].downcase == 'active'
  puts "Starting in active mode..."
  start (:active)

elsif ARGV[0].downcase == 'passive'
  puts "Starting in passive mode..."
  start (:passive)

end
