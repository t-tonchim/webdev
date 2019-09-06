require 'bundler'
Bundler.require
require 'pty'
require 'expect'
require 'timeout'

def getpty(command, conn)
  input, output, _pid = PTY.spawn("docker run --rm -it ruby:latest #{command}")
  buffer = ''
  Timeout.timeout(1) do
    loop { buffer << input.getc }
  end
rescue Timeout::Error
  conn.send(buffer)
  [input, output]
end

@store = {}

EM::WebSocket.start(host: '0.0.0.0', port: 8888) do |conn|
  conn.onopen do |handshake|
    input, output, _pid = getpty(handshake.query['cmd'], conn)

    @store[conn.object_id] = {
      input: input,
      output: output,
    }
  end

  conn.onmessage do |message|
    stream = @store[conn.object_id]
    stream[:output].puts(message)
    finished = false
    response_buffer = ''

    until finished
      stream[:input].expect(/(irb\(main\):\d{3}:0[>*]) |(.*)\n/) do |m|
        conn.close && break if m.nil?

        if m[1]
          response_buffer << "#{m[1]} "
          finished = true
        else
          response_buffer << m[0]
        end
      end
    end

    conn.send(response_buffer)
  end

  conn.onclose do
    @store[conn.object_id].delete
  end

  conn.onerror { |e| p e }
end
