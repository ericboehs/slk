# Ideas

Findings from comparing slk against wee-slack's implementation (Feb 2026).

## Rate Limit Retry with Backoff

`ApiClient` currently raises `ApiError` on 429 responses and dies. For commands like `catchup` and `unread` that make many sequential API calls, an automatic retry with `Retry-After` sleep would prevent aborted runs. wee-slack uses exponential backoff (`tries**2`) and respects the `Retry-After` header.

Relevant file: `lib/slk/services/api_client.rb:176-181`

## Richer Block Kit Rendering

`BlockFormatter` only extracts `section` block text. As Slack moves more content to Block Kit, messages with formatting, code, or lists render as blank or incomplete.

Missing block types:
- `rich_text_list` — ordered/unordered lists with bullets and indent levels
- `rich_text_quote` — blockquotes
- `rich_text_preformatted` — code blocks (triple backtick)
- `divider` — horizontal rules
- `actions` — buttons with URLs
- `call` — huddle/call join links
- `context` — small metadata lines

Missing inline styles within `rich_text_section`:
- Bold, italic, strikethrough, inline code

Relevant file: `lib/slk/formatters/block_formatter.rb`

## Date Token Formatting

Slack's `<!date^timestamp^format|fallback>` tokens appear in scheduled messages, reminders, and bot output. slk doesn't parse these, so they show up as raw tokens. wee-slack implements the full spec including `{date_pretty}` (today/yesterday), `{date_short}`, `{time}`, etc.

Relevant file: `lib/slk/formatters/mention_replacer.rb`

## Attachment Fields

Bot integrations (Jira, PagerDuty, GitHub, etc.) frequently use attachment `fields` — a key-value grid. `AttachmentFormatter` skips these entirely, only rendering `text`/`fallback`, `author`, and `image_url`.

Relevant file: `lib/slk/formatters/attachment_formatter.rb`

## Message Edit Indicators

wee-slack appends `(edited)` to modified messages. slk doesn't surface the `edited` metadata, so edited messages look identical to originals.

Relevant file: `lib/slk/formatters/message_formatter.rb`

## File Attachment Rendering

Messages with inline file attachments (images, PDFs, etc.) aren't rendered. wee-slack shows file title + `url_private`, handles deleted/tombstoned files, and shows storage-limit messages.

Relevant file: `lib/slk/formatters/message_formatter.rb`

## Minor Edge Cases

- **Large timestamp heuristic**: Attachment timestamps > 100000000000 should be treated as milliseconds (divide by 1000). Matches Slack web UI behavior.
- **Notification keywords**: `all_notifications_prefs` contains `global_keywords` that could power filtering or highlighting.
- **Shared channel awareness**: External users (different `team_id`) could be flagged or filtered separately.
