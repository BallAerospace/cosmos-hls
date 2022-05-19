# COSMOS HLS streaming plugin

Check out [this gist](https://gist.github.com/ryan-pratt-ball/18f4c69a96c2c88780211ec3848e52b4) to see how this fits into an end-to-end video streaming demo in COSMOS 5.

This COSMOS 5 plugin runs a microservice to transcode a video stream into HLS with [ffmpeg](https://ffmpeg.org/) to be played back with the [videoplayer plugin](https://github.com/BallAerospace/cosmosc2-tool-videoplayer).

## How to deploy

### For COSMOS Enterprise Edition:

Starting with COSMOS running in a k8s cluster:

1. Create and deploy the docker container
   ```
   > docker build -t cosmos-hls -f Dockerfile-enterprise .
   > docker tag cosmos-hls:latest [url to your container registry]/cosmos-hls:latest
   > docker push [url to your container registry]/cosmos-hls:latest
   ```

1. Create the gem

   First update plugin.txt as needed (see directions below), then run

   ```
   > rake build VERSION=1.0.0
   ```

1. Add the plugin to COSMOS

   a. Log into COSMOS as an admin user

   b. Navigate to the plugin settings (/tools/admin/plugins)

   c. Select and upload the .gem file created at step 4 (it will be named cosmos-hls-stream-1.0.0.gem)

#### plugin.txt

Line 17: This names the microservice. Leave as-is

Line 18: This tells the COSMOS k8s operator what container to use. If you tagged it as something other than cosmos-hls in step 2, update this line with your tag

Line 19: Leave as-is

Line 20: This is the command the container runs when it starts. Leave the "CMD ruby /cosmos/plugins/hls-stream/main.rb" part as-is, but update the four string arguments as needed:

1. This is the name of the stream that appears in the "Open Configuration" dialog of the video player tool. It must be unique from any other streams

1. This is the source URL for the input to ffmpeg

1. This is the public URL to the S3 instance where the video segment files will be stored

1. The bucket in that S3 instance to upload to

1. The list of output formats as a comma delimited list of [width]x[height]@[bitrate]

   a. An example configuration providing four resolutions: 1920x1080@5M,1280x720@2800k,842x480@1498k,640x360@365k

   b. The more output resolutions configured, the more latency there will be as ffmpeg will transcode every output before updating the HLS stream so they're all ready at the same time. It's fine to have only one output format if you know your clients are capable of streaming that format.

   c. Choosing a good bitrate will depend on what's actually in the video, but example bitrates for various resolutions (at 30fps unless specified) are given on lines 6-14. Higher framerates will need higher bitrates. More motion (a panning scene as opposed to a dot that moves across a static background) will need higher bitrates. Using a lower bitrate may add latency on the processing end as the compression algorithm will have to work harder and it can introduce more compression artifacts. However, a lower bitrate will help get a higher resolution stream through a slower internet connection.

1. The H.264 compression preset for ffmpeg to use (ultrafast is usually fine). See the "Preset" section at [Encode/H.264 – FFmpeg](https://trac.ffmpeg.org/wiki/Encode/H.264)

1. The number of channels in the stream. This is typically 2, one for video and one for audio. Streams with 3 or more channels are not supported at this time; the higher numbered channels will simply be dropped during transcoding.

   a. If you get errors from ffmpeg that say something along the lines of "unable to map stream a:0" then your source doesn't have an audio channel, so change this number to 1.

   b. If your source does have audio but you don't want audio in the output, setting this number to 1 should cause the audio channel to get dropped, but this is untested.

### For open-source COSMOS

Starting with COSMOS running locally in Docker:

1. Fill out base.env with your environment variables

1. Create and deploy the docker containers (note: these must be done on the docker host where COSMOS is running)

   ```
   > docker-compose build
   > docker-compose up -d
   ```
