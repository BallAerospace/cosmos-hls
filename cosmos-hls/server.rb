# encoding: ascii-8bit

# Copyright 2021 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
#
# This program is free software; you can modify and/or redistribute it
# under the terms of the GNU Affero General Public License
# as published by the Free Software Foundation; version 3 with
# attribution addendums as found in the LICENSE.txt
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# This program may also be used under the terms of a commercial or
# enterprise edition license of COSMOS if purchased from the
# copyright holder

require 'thread'
require './transcoder'

class Server
  def initialize
    @threads = {}
  end

  def call(env)
    status  = 400 # bad request - this will be changed later if the request is valid
    request = Rack::Request.new(env)

    if request.post? and request.path == '/sls/on_event'
      stream_id = request.params['srt_url']
      key = stream_id.split('/')[-1]
      case request.params['on_event']

      when 'on_connect'
        unless @threads[key]
          thread = Thread.new do
            name = key.split('-').each { |word| word.capitalize! } .join(' ')
            source_url = "#{ENV['SRT_LIVE_SERVER_URL']}?streamid=#{stream_id.gsub(/^input\//, 'output/')}"
            Cosmos::Transcoder.run(name, source_url, ENV['COSMOS_S3_PUBLIC_URL'], 'files', ENV['TRANSCODER_OUTPUT_FORMATS'], 'ultrafast', ENV['TRANSCODER_CHANNELS_PER_STREAM'], cleanup: true)
          end
          @threads[key] = thread
        end
        status = 200 # ok - if SLS gets anything other than a 200, it will refuse the stream connection

      when 'on_close'
        thread = @threads[key]
        if thread
          Thread.kill(thread)
          @threads.delete key
          status = 204 # no content
        else
          status = 404 # not found
        end
      end

    end

    headers = {}
    body = []
    [status, headers, body]
  end
end
