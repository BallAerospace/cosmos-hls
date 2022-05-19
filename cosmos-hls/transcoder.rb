# encoding: ascii-8bit

# Copyright 2022 Ball Aerospace & Technologies Corp.
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

require 'aws-sdk-s3'
require 'base64'
require 'rufus-scheduler'
require 'tmpdir'
require 'cosmos'
require 'cosmos/api/api'

Aws.config.update(
  endpoint: ENV['COSMOS_S3_URL'] || (ENV['COSMOS_DEVEL'] ? 'http://127.0.0.1:9000' : 'http://cosmos-minio:9000'),
  access_key_id: ENV['COSMOS_MINIO_USERNAME'],
  secret_access_key: ENV['COSMOS_MINIO_PASSWORD'],
  force_path_style: true,
  region: 'us-west-1'
)

module Cosmos
  class Transcoder
    include Api
    
    SHUTDOWN_DELAY_SECS = 2
    HLS_LIST_SIZE = 8
    HLS_TIME = 2 # seconds

    def initialize(bucket)
      @bucket = bucket

      @rubys3_client = Aws::S3::Client.new
      begin
        @rubys3_client.head_bucket(bucket: @bucket)
      rescue Aws::S3::Errors::NotFound
        @rubys3_client.create_bucket(bucket: @bucket)
      end

      policy = <<EOL
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "s3:GetBucketLocation",
        "s3:ListBucket"
      ],
      "Effect": "Allow",
      "Principal": {
        "AWS": [
          "*"
        ]
      },
      "Resource": [
        "arn:aws:s3:::files"
      ],
      "Sid": ""
    },
    {
      "Action": [
        "s3:GetObject"
      ],
      "Effect": "Allow",
      "Principal": {
        "AWS": [
          "*"
        ]
      },
      "Resource": [
        "arn:aws:s3:::files/*"
      ],
      "Sid": ""
    }
  ]
}
EOL

      @rubys3_client.put_bucket_policy({bucket: @bucket, policy: policy})

    end

    def encode_hls(source_path, output_dir, manifest_pl_name, base_url, formats, codec_preset, num_streams)
      codec = "libx264"
      map_config = ""
      var_stream_map = ""
      formats.each_with_index do |format, index| # format is something like "640x360@365k"
        resolution, bitrate = format.split('@')
        map_config.prepend("-map 0:0 -map 0:1? ") # no #{index} in this part - this is identical for each output stream. It maps in streams 0 (video) and 1 (audio, if it exists) from the input
        map_config << "-s:v:#{index} #{resolution} -c:v:#{index} #{codec} -b:v:#{index} #{bitrate} "
        var_stream_map << " v:#{index}"
        var_stream_map << ",a:#{index}" unless num_streams == 1 # -var_stream_map doesn't support the ? for the audio stream like the map config does
      end
      map_config.strip! # something like "-map 0:0 -map 0:1? -map 0:0 -map 0:1? -s:v:0 640x360 -c:v:0 libx264 -b:v:0 365k -s:v:1 960x540 -c:v:1 libx264 -b:v:1 2000k"
      var_stream_map.strip! # something like "v:0,a:0 v:1,a:1"

      system("ffmpeg -y -i #{source_path} -preset #{codec_preset} -sc_threshold 0 #{map_config} -c:a copy -var_stream_map \"#{var_stream_map}\" -master_pl_name #{manifest_pl_name} -f hls -hls_time #{HLS_TIME} -hls_list_size #{HLS_LIST_SIZE} -hls_base_url \"#{base_url}\" -hls_segment_filename \"#{output_dir}/v%v-seq%d.ts\" #{output_dir}/v%v-index.m3u8")
    end

    def upload_output_segments(output_dir, minio_path)
      existing_keys = @rubys3_client.list_objects(bucket: @bucket, prefix: minio_path).contents.map { |object| object.key }
      Dir::glob("#{output_dir}/*.ts").each do |segment_path|
        File.open(segment_path, 'r') do |file|
          key = "#{minio_path}#{segment_path.sub(output_dir, '')}"
          @rubys3_client.put_object(bucket: @bucket, key: key, body: file) unless existing_keys.include? key # Don't reupload files that are already there
        end
      end
    end

    def playlists_to_config(output_dir, manifest_pl_name)
      return unless File.file?("#{output_dir}/#{manifest_pl_name}") # Make sure it's ready first
      playlists = {
        :manifest => nil,
        :indexes => {}
      }
      manifest_file = File.read("#{output_dir}/#{manifest_pl_name}")
      playlists[:manifest] = Base64.encode64(manifest_file)
      Dir::glob("#{output_dir}/*.m3u8").each do |playlist_path|
        file = File.read(playlist_path)
        index = playlist_path.sub("#{output_dir}/", '')
        playlists[:indexes][index] = Base64.encode64(file)
      end
      playlists
    end

    def prune_segments(output_dir, minio_path)
      objects_to_delete = []
      Dir::glob("#{output_dir}/*.ts").group_by { |key| key.split('/')[-1].split('-')[0] }.values.each do |group|
        group.sort_by { |segment_path| Integer(/(\d+)(?!.*\d)/.match(segment_path)[0]) }.reverse.drop(HLS_LIST_SIZE * HLS_TIME * 2).each do |segment_path|
          File.delete(segment_path) if File.exists? segment_path
          objects_to_delete << { :key => "#{minio_path}#{segment_path.sub(output_dir, '')}" }
        end
      end
      
      @rubys3_client.delete_objects({ bucket: @bucket, delete: { objects: objects_to_delete } } ) if objects_to_delete.length > 0
    end

    def self.run(stream_name, source_path, s3_public_url, bucket, formats_string, codec_preset, num_streams, cleanup: false)
      num_streams = Integer(num_streams)
      scope = ENV['COSMOS_SCOPE']
      tool_name = 'video-player'
      output_path = "video/#{stream_name.sub(' ', '-')}" #path in minio
      temp_dir = Dir.mktmpdir
      begin
        transcoder = self.new(bucket)
        manifest_pl_name = 'manifest.m3u8'

        # Loop forever to capture and deliver its output
        delivery_thread = Rufus::Scheduler.new
        delivery_thread.cron "*/#{HLS_TIME} * * * * *" do
          transcoder.upload_output_segments(temp_dir, output_path)
          tool_config = transcoder.playlists_to_config(temp_dir, manifest_pl_name)
          transcoder.save_config(tool_name, stream_name, tool_config.to_json, scope: scope, token: ENV['COSMOS_SERVICE_PASSWORD']) if tool_config # method is from config_api.rb
          transcoder.prune_segments(temp_dir, output_path)
        end

        # This will run forever for live video
        encoding_thread = Thread.new do
          transcoder.encode_hls(source_path, temp_dir, manifest_pl_name, "#{s3_public_url}/#{bucket}/#{output_path}/", formats_string.split(','), codec_preset, num_streams)
          delivery_thread.shutdown(wait: SHUTDOWN_DELAY_SECS) if delivery_thread
          if cleanup
            # TODO
          end
        end

        [encoding_thread, delivery_thread].each(&:join)
      rescue SystemExit, Interrupt
        delivery_thread.shutdown(wait: SHUTDOWN_DELAY_SECS) if delivery_thread
        if cleanup
          # TODO
        end
        FileUtils.remove_entry(temp_dir) if File.exist?(temp_dir)
      end
    end
  end
end

Cosmos::Transcoder.run(ARGV[0], ARGV[1], ARGV[2], ARGV[3], ARGV[4], ARGV[5], ARGV[6]) if __FILE__ == $0
