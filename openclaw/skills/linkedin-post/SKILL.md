---
name: linkedin-post
description: Draft, review, and publish LinkedIn posts via HMAC-signed webhook to n8n
requires:
  env:
    - N8N_WEBHOOK_SECRET
  bins:
    - curl
    - jq
    - openssl
---

# LinkedIn Post

When the operator asks to draft or publish a LinkedIn post, use this skill.

## Supported Content Types

- **text**: Plain text post (default)
- **article**: Post with a URL, custom title, and description
- **image**: Post with an uploaded image (operator must provide the image)

If the operator requests an unsupported type (e.g., "reshare this post",
"post a video"), inform them: "I can create text posts, article shares,
and image posts. For that content, I can draft a text post commenting on
it instead. Would you like me to do that?"

## Workflow

### 1. Draft Content

Generate a draft using SOUL.md voice and AGENTS.md rules:

- Incorporate the operator's topic or instructions
- Apply content boundaries (no false claims, no competitor bashing)
- Keep to 150-300 words for posts
- Vary format based on recent posting history

### 2. Present for Review

Show the draft to the operator:

```text
Here's a draft post about [topic]:

---
[draft content]
---

Type "approve" to publish, or tell me what to change.
```

### 3. Handle Operator Response

- **"approve" / "post it" / "yes"**: Proceed to publish
- **"reject" / "no" / "skip"**: Discard draft, confirm: "Draft discarded."
- **Edit request**: Revise draft, re-present for approval
- **Image request without image**: "Please send the image and I'll create
  the post."

### 4. Persist Draft State

On draft creation, write to pending-drafts.json:

```bash
DRAFT_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
DRAFTS_FILE="$HOME/.openclaw/agents/linkedin-persona/pending-drafts.json"

# Read existing or create empty array
if [ -f "$DRAFTS_FILE" ]; then
  DRAFTS=$(cat "$DRAFTS_FILE")
else
  DRAFTS="[]"
fi

# Add new draft
echo "$DRAFTS" | jq --arg id "$DRAFT_ID" \
  --arg type "$CONTENT_TYPE" \
  --arg content "$DRAFT_CONTENT" \
  --arg status "presented" \
  '. + [{"id": $id, "type": $type, "content": $content, "status": $status, "created_at": (now | todate)}]' \
  > "$DRAFTS_FILE"
```

### 5. Publish via Webhook

On approval, compute HMAC and POST to n8n:

```bash
WEBHOOK_URL="http://localhost:5678/webhook/linkedin-post"
TIMESTAMP=$(date +%s)
BODY='{"action":"publish_post","draft_id":"'"$DRAFT_ID"'","content_type":"'"$CONTENT_TYPE"'","text":"'"$DRAFT_CONTENT"'"}'

SIGNATURE="sha256=$(echo -n "$BODY" | openssl dgst -sha256 -hmac "$N8N_WEBHOOK_SECRET" | awk '{print $2}')"

RESPONSE=$(curl -s -X POST "$WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -H "X-Signature: $SIGNATURE" \
  -H "X-Timestamp: $TIMESTAMP" \
  -d "$BODY")

STATUS=$(echo "$RESPONSE" | jq -r '.status')
```

### 6. Confirm or Alert

- **Published**: "Posted! Here's the link: [linkedin_post_url]"
- **Error (token_expired)**: "LinkedIn token has expired. Please
  re-authorize in n8n. Post saved for retry."
- **Error (rate_limited)**: "LinkedIn rate limit reached. I'll try again
  later."
- **Error (other)**: "Post failed: [error_message]. The draft is saved."

### 7. Update Draft State

After resolution, update pending-drafts.json:

```bash
jq --arg id "$DRAFT_ID" --arg status "$FINAL_STATUS" \
  'map(if .id == $id then .status = $status | .resolved_at = (now | todate) else . end)' \
  "$DRAFTS_FILE" > "${DRAFTS_FILE}.tmp" && mv "${DRAFTS_FILE}.tmp" "$DRAFTS_FILE"
```
