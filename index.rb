#!/usr/bin/env ruby

require 'socket'
require 'uri'
require 'net/http'
require 'logger'

class WeightedReverseProxy
  def initialize(port = 8080)
    @port = port
    @logger = Logger.new(STDOUT)
    @logger.level = Logger::INFO

    # Define backend servers with weights
    # Weights represent relative traffic distribution (e.g., 70-30 split)
    @backends = [
      { url: 'http://bostonrb.dartbuilt.com:3000', weight: 70 },
      { url: 'http://bostonrb.dartbuilt.com:3001', weight: 30 }
    ]

    # Normalize weights to ensure they sum to 100
    total_weight = @backends.sum { |b| b[:weight] }
    @backends.each { |b| b[:weight] = (b[:weight].to_f / total_weight * 100).round(2) }

    @logger.info "Initialized reverse proxy with backend weights:"
    @backends.each do |backend|
      @logger.info "  #{backend[:url]}: #{backend[:weight]}%"
    end
  end

  def start
    server = TCPServer.new(@port)
    @logger.info "Reverse proxy listening on port #{@port}"

    loop do
      Thread.start(server.accept) do |client|
        handle_client(client)
      end
    end
  rescue StandardError => e
    @logger.error "Server error: #{e.message}"
    @logger.error e.backtrace.join("\n")
  end

  private

  def handle_client(client)
    request_line = client.readline
    method, path, version = request_line.split

    # Read headers
    headers = {}
    while (line = client.readline.strip) && !line.empty?
      key, value = line.split(': ', 2)
      headers[key.downcase] = value
    end

    # Read body if present
    body = ''
    if headers['content-length']
      body = client.read(headers['content-length'].to_i)
    end

    # Select backend based on weighted distribution
    backend = select_backend

    # Forward request to backend
    response = forward_request(method, path, headers, body, backend)

    # Send response back to client
    client.write(response)
    client.close
  rescue StandardError => e
    @logger.error "Error handling client request: #{e.message}"
    send_error_response(client, e)
  end

  def select_backend
    # Generate random number between 0 and 100
    rand_num = rand(100)

    # Calculate cumulative weights and select backend
    cumulative_weight = 0
    @backends.each do |backend|
      cumulative_weight += backend[:weight]
      return backend if rand_num <= cumulative_weight
    end

    # Fallback to first backend if something goes wrong
    @backends.first
  end

  def forward_request(method, path, headers, body, backend)
    puts path
    if path == '/up'
      return "HTTP/0.9 200 OK"
    end

    uri = URI(backend[:url] + path)

    # Create new request
    request = Net::HTTP.const_get(method.capitalize).new(uri)

    # Set headers
    headers.each do |key, value|
      request[key] = value unless ['host', 'connection'].include?(key)
    end

    # Set body if present
    request.body = body if body && !body.empty?

    # Add proxy headers
    request['X-Forwarded-For'] = headers['x-forwarded-for'] || headers['remote_addr']
    request['X-Forwarded-Proto'] = 'http'
    request['X-Forwarded-Host'] = headers['host']

    # Send request
    response = Net::HTTP.start(uri.host, uri.port) do |http|
      http.request(request)
    end

    # Log the request
    @logger.info "#{method} #{path} -> #{backend[:url]} (#{response.code})"

    # Build response
    "HTTP/1.1 #{response.code} #{response.message}\r\n" +
    response.each_header.map { |k,v| "#{k}: #{v}\r\n" }.join +
    "\r\n" +
    response.body.to_s
  end

  def send_error_response(client, error)
    response = "HTTP/1.1 500 Internal Server Error\r\n" +
               "Content-Type: text/plain\r\n" +
               "\r\n" +
               "Error: #{error.message}"
    client.write(response)
    client.close
  end
end

# Usage example
if __FILE__ == $0
  proxy = WeightedReverseProxy.new(8080)
  proxy.start
end
