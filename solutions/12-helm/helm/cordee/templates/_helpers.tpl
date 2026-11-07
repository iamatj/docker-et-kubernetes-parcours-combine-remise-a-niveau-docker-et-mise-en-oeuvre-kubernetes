{{/* Étiquettes communes à tous les objets du chart. */}}
{{- define "cordee.labels" -}}
partie-de: cordee
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}

{{/* Image complète d'un composant : {{ include "cordee.image" .Values.api }} */}}
{{- define "cordee.image" -}}
{{ .image.repository }}:{{ .image.tag }}
{{- end -}}
