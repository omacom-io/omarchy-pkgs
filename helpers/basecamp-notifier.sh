# Send notifications to Basecamp Campfire via chatbot
#
# Requires BASECAMP_CHATBOT_URL environment variable to be set.
# This is the full chatbot lines URL from Basecamp, e.g.:
#   https://3.basecamp.com/<account>/integrations/<key>/buckets/<project>/chats/<chat>/lines
#
# If BASECAMP_CHATBOT_URL is not set, notifications are silently skipped.

notify_basecamp() {
  local content="$1"

  if [[ -z "${BASECAMP_CHATBOT_URL:-}" ]]; then
    return 0
  fi

  curl -s -o /dev/null \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg content "$content" '{content: $content}')" \
    "$BASECAMP_CHATBOT_URL" 2>/dev/null || true
}

basecamp_html_escape() {
  sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

basecamp_strip_ansi() {
  sed -E $'s/\x1B\\[[0-9;?]*[ -/]*[@-~]//g'
}

basecamp_format_log_tail_html() {
  local log_file="$1"
  local lines="${2:-25}"

  [[ -n "$log_file" && -f "$log_file" ]] || return 0

  tail -n "$lines" "$log_file" 2>/dev/null |
    tr -d '\r' |
    basecamp_strip_ansi |
    basecamp_html_escape |
    sed ':a;N;$!ba;s/\n/<br>/g'
}

notify_error() {
  local title="$1"
  local details="${2:-}"
  local log_file="${OMARCHY_LOG_FILE:-${LOG_FILE:-}}"
  local log_tail_lines="${BASECAMP_LOG_TAIL_LINES:-25}"
  local log_tail=""

  local content="🔴 <strong>${title}</strong>"
  if [[ -n "$details" ]]; then
    content+="<br>${details}"
  fi

  log_tail=$(basecamp_format_log_tail_html "$log_file" "$log_tail_lines")
  if [[ -n "$log_tail" ]]; then
    content+="<br><br><strong>Last ${log_tail_lines} log lines:</strong><br><code>${log_tail}</code>"
  fi

  notify_basecamp "$content"
}

