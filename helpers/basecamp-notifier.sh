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

notify_error() {
  local title="$1"
  local details="${2:-}"

  local content="🔴 <strong>${title}</strong>"
  if [[ -n "$details" ]]; then
    content+="<br>${details}"
  fi

  notify_basecamp "$content"
}

