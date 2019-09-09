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
      buf: ''
    }
  end

  conn.onmessage do |message|
    stream = @store[conn.object_id]
    if message != "\r"
      if message == "\u007F"
        next if stream[:buf].length == 0

        stream[:buf] = stream[:buf].slice(0, stream[:buf].length - 1)
        conn.send("\b \b")
      else
        stream[:buf] << message
        conn.send(message)
      end
    else
      stream[:buf] << "\r"
      stream[:output].print(stream[:buf])
      finished = false
      response_buffer = stream[:buf].chomp == "" ? "\n\r" : "\r"

      until finished
        stream[:input].expect(/(irb\(main\):\d{3}:0[>*]) |(.*)\R/) do |m|
          conn.close && break if m.nil?

          if m[1]
            response_buffer << "#{m[1]} "
            finished = true
          else
            response_buffer << m[0] if stream[:buf].chomp != m[0].chomp #|| m[0].chomp != ''
          end
        end
      end

      stream[:buf] = ''
      conn.send(response_buffer)
    end
  end

  conn.onclose do
    @store[conn.object_id].delete
  end

  conn.onerror { |e| p e }
end
