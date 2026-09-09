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
