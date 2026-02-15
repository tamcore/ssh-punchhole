{{- define "ssh-punchhole.podSpec" }}
{{- if $.Values.metrics.enabled }}
shareProcessNamespace: true
{{- end }}
{{- with $.Values.podSecurityContext }}
securityContext:
  {{- toYaml . | nindent 2 }}
{{- end }}
containers:
- name: {{ include "charts.fullname" $ }}
  image: {{ $.Values.image.repository }}:{{ $.Values.image.tag | default $.Chart.AppVersion }}
  imagePullPolicy: {{ $.Values.image.pullPolicy }}
  {{- with $.Values.command }}
  command:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $.Values.args }}
  args:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $.Values.securityContext }}
  securityContext:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  env:
  {{- range $k, $v := mergeOverwrite (.config) (dict "IDENTITYFILE" "/ssh/id_rsa" "KNOWN_HOSTS" "/ssh/known_hosts") }}
  - name: "{{ $k }}"
    value: "{{ $v }}"
  {{- end }}
  volumeMounts:
  - name: ssh-data
    mountPath: "/ssh"
    readOnly: true
  - name: tmp
    mountPath: "/tmp"
  {{- if $.Values.resources }}
  resources: {{- toYaml $.Values.resources | nindent 4 }}
  {{- end }}
  {{- if $.Values.healthcheck.enabled }}
  livenessProbe:
    exec:
      command: ["/healthcheck.sh"]
    initialDelaySeconds: {{ $.Values.healthcheck.livenessProbe.initialDelaySeconds }}
    periodSeconds: {{ $.Values.healthcheck.livenessProbe.periodSeconds }}
    timeoutSeconds: {{ $.Values.healthcheck.livenessProbe.timeoutSeconds }}
    failureThreshold: {{ $.Values.healthcheck.livenessProbe.failureThreshold }}
  readinessProbe:
    exec:
      command: ["/healthcheck.sh"]
    initialDelaySeconds: {{ $.Values.healthcheck.readinessProbe.initialDelaySeconds }}
    periodSeconds: {{ $.Values.healthcheck.readinessProbe.periodSeconds }}
    timeoutSeconds: {{ $.Values.healthcheck.readinessProbe.timeoutSeconds }}
    failureThreshold: {{ $.Values.healthcheck.readinessProbe.failureThreshold }}
  {{- end }}
  {{- if or $.Values.postStart.command $.Values.lifecycle.preStop.enabled }}
  lifecycle:
    {{- if $.Values.postStart.command }}
    postStart:
      exec:
        command: {{ toYaml $.Values.postStart.command | nindent 8 }}
    {{- end }}
    {{- if $.Values.lifecycle.preStop.enabled }}
    preStop:
      exec:
        command: ["/bin/sh", "-c", "sleep {{ $.Values.lifecycle.preStop.sleepSeconds }}"]
    {{- end }}
  {{- end }}
{{- if $.Values.metrics.enabled }}
- name: metrics-collector
  image: {{ $.Values.image.repository }}:{{ $.Values.image.tag | default $.Chart.AppVersion }}
  imagePullPolicy: {{ $.Values.image.pullPolicy }}
  command: ["/metrics-collector.sh"]
  ports:
  - containerPort: 9090
    name: metrics
    protocol: TCP
  env:
  - name: METRICS_DIR
    value: "/metrics"
  - name: METRICS_COLLECTION_INTERVAL
    value: "{{ $.Values.metrics.collectionInterval }}"
  - name: REMOTE_HOST
    value: "{{ .config.REMOTE_HOST }}"
  - name: SSH_PORT
    value: "{{ .config.SSH_PORT }}"
  - name: HTTP_PORT
    value: "9090"
  volumeMounts:
  - name: metrics
    mountPath: /metrics
  {{- if $.Values.metrics.resources }}
  resources: {{- toYaml $.Values.metrics.resources | nindent 4 }}
  {{- end }}
  securityContext:
    capabilities:
      drop:
      - all
    readOnlyRootFilesystem: false
{{- end }}
volumes:
- name: ssh-data
  secret:
    {{- if not $.Values.data.existingSecret }}
    secretName: {{ include "charts.fullname" $ }}-data
    {{- else }}
    secretName: {{ $.Values.data.existingSecret }}
    {{- end }}
- name: tmp
  emptyDir: {}
{{- if $.Values.metrics.enabled }}
- name: metrics
  emptyDir: {}
{{- end }}
{{- end }}
