{{- define "fishers-postgres.name" -}}fishers-postgres{{- end -}}

{{- define "fishers-postgres.labels" -}}
app.kubernetes.io/name: fishers-postgres
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: database
app.kubernetes.io/part-of: fishers
app.kubernetes.io/managed-by: {{ .Release.Service }}
fishers.cloud/env: {{ .Values.env | quote }}
{{- end -}}

{{- define "fishers-postgres.selectorLabels" -}}
app.kubernetes.io/name: fishers-postgres
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
