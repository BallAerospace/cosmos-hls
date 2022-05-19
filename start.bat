docker build -t cosmos-hls -f ./cosmos-hls/Dockerfile ./cosmos-hls
docker run -d --env-file=.\base.env --network cosmos_default --hostname hls-transcoder --name hls-transcoder_hls-transcoder_1 cosmos-hls
docker run -d -p 1935:1935/udp --volume=%CD%\srt-live-server\sls.conf:/etc/sls/sls.conf:ro --volume=%CD%\srt-live-server\logs:/logs --network cosmos_default --hostname srt-live-server --name hls-transcoder_srt-live-server_1 ravenium/srt-live-server
