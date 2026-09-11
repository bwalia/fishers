{{- define "fishers-api.name" -}}fishers-api{{- end -}}

{{- define "fishers-api.labels" -}}
app.kubernetes.io/name: fishers-api
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: api
app.kubernetes.io/part-of: fishers
app.kubernetes.io/managed-by: {{ .Release.Service }}
fishers.cloud/env: {{ .Values.env | quote }}
{{- end -}}

{{- define "fishers-api.selectorLabels" -}}
app.kubernetes.io/name: fishers-api
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "fishers-api.hostname" -}}
{{- if not .Values.hostname }}{{- fail "hostname is empty. Set it in values-<env>.yaml — it becomes PUBLIC_WEB_BASE, which is baked into every share link the API mints." }}{{- end }}
{{- .Values.hostname }}
{{- end -}}

{{- /* The Secret the Zalando operator writes the owner's credentials into. */ -}}
{{- define "fishers-api.dbSecret" -}}
{{ .Values.db.owner }}.{{ .Values.db.clusterName }}.credentials.postgresql.acid.zalan.do
{{- end -}}
