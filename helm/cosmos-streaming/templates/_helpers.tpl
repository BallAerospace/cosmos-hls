{{/*
# Copyright 2020 Ball Aerospace & Technologies Corp.
# All Rights Reserved.
*/}}

{{/*
Create the kubernetes name based on the Release and Template names
*/}}
{{- define "cosmos.name" -}}
{{ .Release.Name }}-{{ base .Template.Name | trimSuffix ".yaml" | trimSuffix "-service" | trimSuffix "-deployment" | camelcase | kebabcase | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Container registry for the container
*/}}
{{- define "cosmos.registry" -}}
{{- if .Values.global.image.registry }}
{{- .Values.global.image.registry }}
{{- else if .Values.global.aws.enabled }}
{{- printf "%s.dkr.ecr.%s.amazonaws.com" .Values.global.aws.account .Values.global.aws.region }}
{{- else }}
{{- printf "localhost:5000" }}
{{- end }}
{{- end }}

{{/*
Create the environment variables for the transcoder
*/}}
{{- define "transcoder.env" -}}
- name: SRT_LIVE_SERVER_URL
  value: {{ printf "srt://%s-srt-live-server:1935" .Release.Name }}
- name: TRANSCODER_OUTPUT_FORMATS
  value: {{ .Values.transcoder.outputFormats }}
- name: TRANSCODER_CHANNELS_PER_STREAM
  value: {{ .Values.transcoder.channelsPerStream }}
{{- end }}

{{/*
Create the environment variables for COSMOS containers
*/}}
{{- define "cosmos.env" -}}
- name: COSMOS_REDIS_URL
  value: {{ printf "redis://%s-redis-cluster:6379" .Values.cosmos.installationName }}
- name: COSMOS_REDIS_HOST
  value: {{ printf "%s-redis-cluster:6379" .Values.cosmos.installationName }}
- name: COSMOS_S3_URL
  value: {{ printf "http://%s-minio:9000" .Values.cosmos.installationName }}

- name: COSMOS_S3_PUBLIC_URL
  value: {{ .Values.cosmos.s3PublicUrl }}
- name: COSMOS_SCOPE
  value: {{ printf "%s" .Values.cosmos.scope }}
{{- end }}

{{/*
Create the environment variables for COSMOS REDIS user
*/}}
{{- define "cosmos.redis-env" -}}
- name: COSMOS_REDIS_USERNAME
  valueFrom:
    secretKeyRef:
      name: streaming-redis-creds
      key: username
- name: COSMOS_REDIS_PASSWORD
  valueFrom:
    secretKeyRef:
      name: streaming-redis-creds
      key: password
{{- end }}

{{/*
Create the environment variables for COSMOS MINIO user
*/}}
{{- define "cosmos.minio-env" -}}
- name: COSMOS_MINIO_USERNAME
  valueFrom:
    secretKeyRef:
      name: streaming-minio-creds
      key: username
- name: COSMOS_MINIO_PASSWORD
  valueFrom:
    secretKeyRef:
      name: streaming-minio-creds
      key: password
{{- end }}

{{/*
Create the environment variables for COSMOS SERVICE user
*/}}
{{- define "cosmos.service-password" -}}
- name: COSMOS_SERVICE_PASSWORD
  valueFrom:
    secretKeyRef:
      name: streaming-cosmos-auth
      key: password
{{- end }}
