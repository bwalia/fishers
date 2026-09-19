{{- define "fishers-web.name" -}}fishers-web{{- end -}}

{{- define "fishers-web.labels" -}}
app.kubernetes.io/name: fishers-web
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: web
app.kubernetes.io/part-of: fishers
app.kubernetes.io/managed-by: {{ .Release.Service }}
fishers.cloud/env: {{ .Values.env | quote }}
{{- end -}}

{{- define "fishers-web.selectorLabels" -}}
app.kubernetes.io/name: fishers-web
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "fishers-web.hostname" -}}
{{- if not .Values.hostname }}{{- fail "hostname is empty. Set it in values-<env>.yaml — it is the ingress rule, and without it the release claims no host at all." }}{{- end }}
{{- .Values.hostname }}
{{- end -}}

{{/* The gateway's Service in this namespace, for a ring that has one. */}}
{{- define "fishers-web.kongServiceName" -}}
{{- if .Values.kong.serviceName }}{{- .Values.kong.serviceName }}
{{- else }}{{- printf "kong-fishers-%s-kong-proxy" .Values.env }}{{- end }}
{{- end -}}

{{/* What /api, /swagger-ui and /health are sent to: Kong where the ring has it,
     fishers-api where it does not. Name and port answer as a pair, so a chart
     edit cannot send the gateway's port to the API. */}}
{{- define "fishers-web.apiBackendName" -}}
{{- if .Values.kong.enabled }}{{- include "fishers-web.kongServiceName" . }}
{{- else }}{{- .Values.apiServiceName }}{{- end }}
{{- end -}}

{{- define "fishers-web.apiBackendPort" -}}
{{- if .Values.kong.enabled }}{{- .Values.kong.servicePort }}
{{- else }}{{- .Values.apiServicePort }}{{- end }}
{{- end -}}
