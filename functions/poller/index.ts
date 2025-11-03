import { getEnvConfig } from "../../src/utils/config";
import { listUnreadLimited, getMessageFull, extractPlainTextFromMessage, sendReply, markRepliedAndLabel } from "../../src/clients/gmail";
import { upsertEmail, upsertEmbedding, recordReply } from "../../src/clients/db";
import { embedText, generateInsight } from "../../src/clients/openai";
import { retrieveContext } from "../../src/rag/retriever";
import { buildPrompt } from "../../src/rag/prompt";

export const handler = async () => {
  const env = getEnvConfig();
  const messages = await listUnreadLimited(env.batchSize);
  if (!messages.length) return { processed: 0 };

  let processed = 0;
  for (const m of messages) {
    try {
      const full = await getMessageFull(m.id);
      const meta = extractPlainTextFromMessage(full);
      const email = await upsertEmail({
        gmail_message_id: m.id,
        gmail_thread_id: m.threadId,
        from_address: meta.from,
        to_address: meta.to,
        subject: meta.subject,
        snippet: full.snippet,
        body_text: meta.bodyText,
      });

      const bodyEmbedding = await embedText(meta.bodyText || "");
      await upsertEmbedding(email.id, bodyEmbedding);

      const { context } = await retrieveContext(meta.bodyText || meta.subject || "", 5);
      const prompt = buildPrompt({ question: meta.bodyText || meta.subject || "", context });
      const ai = await generateInsight(prompt);

      // Determine reply address
      const toMatch = /<(.*?)>/.exec(meta.from);
      const toAddress = toMatch ? toMatch[1] : meta.from;

      await sendReply({ threadId: m.threadId, to: toAddress, subject: meta.subject || "Your question", body: ai.text, inReplyTo: meta.messageIdHeader });
      await markRepliedAndLabel({ messageId: m.id, addLabel: env.gmailLabelReplied, removeUnread: true });
      await recordReply(email.id, ai.model, ai.text, ai.usage?.prompt_tokens, ai.usage?.completion_tokens);
      processed += 1;
    } catch (err) {
      console.error("process_error", { messageId: m.id, error: String(err) });
    }
  }

  return { processed };
};

