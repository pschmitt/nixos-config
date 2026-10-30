import { sendMessage, getThreadMessages, editMessage } from 'msteams-mcp/dist/api/chatsvc-messaging.js';
import { addReaction, removeReaction } from 'msteams-mcp/dist/api/chatsvc-reactions.js';
import { markdownToTeamsHtml } from 'msteams-mcp/dist/utils/parsers-markdown.js';

export { sendMessage, getThreadMessages, editMessage, addReaction, removeReaction, markdownToTeamsHtml };

export const botSentMessageIds = new Set();

export function recordBotMessageId(id) {
  if (id) {
    const s = String(id);
    botSentMessageIds.add(s);
    if (/^\d{12,14}$/.test(s)) {
      const num = Number(s);
      try {
        botSentMessageIds.add(new Date(num).toISOString());
      } catch {}
    } else {
      const parsed = Date.parse(s);
      if (!isNaN(parsed)) {
        botSentMessageIds.add(String(parsed));
      }
    }
    if (botSentMessageIds.size > 2000) {
      const iter = botSentMessageIds.values();
      botSentMessageIds.delete(iter.next().value);
    }
  }
}

export const STATUS_REACTIONS = {
  pending: '1f440_eyes', // 👀 needs approval
  approved: 'like', // 👍 approved, not merged
  merged: '2705_whiteheavycheckmark', // ✅
  failed: '274c_crossmark', // ❌ CI failed
};

export const COMMAND_REACTIONS = {
  success: '2705_whiteheavycheckmark', // ✅
  failure: '274c_crossmark', // ❌
  warning: '26a0_warning', // ⚠️
  running: '23f3_hourglass', // ⏳
};

export const STATUS_BY_REACTION = new Map(
  Object.entries(STATUS_REACTIONS).map(([status, key]) => [key, status])
);

export function escapeHtml(text) {
  return String(text ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

/**
 * Builds a Teams blockquote quoting an existing message.
 * This is how Teams client renders threaded replies in chats and meetings.
 */
export function buildQuotedReplyHtml({ messageId, from, fromMri, previewText, replyMarkdown }) {
  const quote =
    `<blockquote itemscope="" itemtype="http://schema.skype.com/Reply" itemid="${escapeHtml(messageId)}">` +
    `<strong itemprop="mri" itemid="${escapeHtml(fromMri || '')}">${escapeHtml(from || '')}</strong>` +
    `<span itemprop="time" itemid="${escapeHtml(messageId)}"></span>` +
    `<p itemprop="preview">${escapeHtml(previewText || '')}</p>` +
    '</blockquote>';

  return quote + markdownToTeamsHtml(replyMarkdown);
}

/**
 * Sends a reply to a message in a conversation.
 * Handles both channel threads (@thread.tacv2) and chat/meeting quote-replies.
 */
export async function sendReply(conversationId, originalMessage, replyMarkdown) {
  const isChannel = conversationId.endsWith('@thread.tacv2');
  const messageId = originalMessage.messageId || originalMessage.id;
  const from = originalMessage.from || originalMessage.sender?.displayName || '';
  const fromMri = originalMessage.fromMri || originalMessage.sender?.mri || '';
  const previewText = (originalMessage.content || originalMessage.text || '').slice(0, 150);

  const html = buildQuotedReplyHtml({
    messageId,
    from,
    fromMri,
    previewText,
    replyMarkdown,
  });

  const options = {
    contentType: 'html',
  };

  if (isChannel) {
    options.replyToMessageId = messageId;
  }

  const result = await sendMessage(conversationId, html, options);
  if (result.ok && result.value) {
    recordBotMessageId(result.value.timestamp);
    recordBotMessageId(result.value.messageId);
  }
  return result;
}

/**
 * Updates an existing reply message in-place.
 */
export async function updateReply(conversationId, serverMessageId, originalMessage, replyMarkdown) {
  recordBotMessageId(serverMessageId);
  const messageId = originalMessage.messageId || originalMessage.id;
  const from = originalMessage.from || originalMessage.sender?.displayName || '';
  const fromMri = originalMessage.fromMri || originalMessage.sender?.mri || '';
  const previewText = (originalMessage.content || originalMessage.text || '').slice(0, 150);

  const html = buildQuotedReplyHtml({
    messageId,
    from,
    fromMri,
    previewText,
    replyMarkdown,
  });

  return await editMessage(conversationId, String(serverMessageId), html, 'html');
}
