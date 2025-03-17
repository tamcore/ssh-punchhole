{{- define "ssh-punchhole.podSpec" }}
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
  {{- if $.Values.resources }}
  resources: {{- toYaml $.Values.resources | nindent 4 }}
  {{- end }}
  {{- if $.Values.postStart.command }}
  lifecycle:
    postStart:
      exec:
        command: {{ toYaml $.Values.postStart.command | nindent 8 }}
  {{- end }}
volumes:
- name: ssh-data
  secret:
    {{- if not $.Values.data.existingSecret }}
    secretName: {{ include "charts.fullname" $ }}-data
    {{- else }}
    secretName: {{ $.Values.data.existingSecret }}
    {{- end }}
{{- end }}
