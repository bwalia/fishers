{{- define "fishers-minio.name" -}}fishers-minio{{- end -}}

{{- define "fishers-minio.labels" -}}
app.kubernetes.io/name: fishers-minio
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: object-storage
app.kubernetes.io/part-of: fishers
app.kubernetes.io/managed-by: {{ .Release.Service }}
fishers.cloud/env: {{ .Values.env | quote }}
{{- end -}}

{{- define "fishers-minio.selectorLabels" -}}
app.kubernetes.io/name: fishers-minio
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
