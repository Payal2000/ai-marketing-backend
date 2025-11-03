import { google } from "googleapis";
import type { OAuth2Client } from "google-auth-library";
import { getConfig, getEnvConfig } from "../utils/config";

type GmailMessage = {
  id: string;
  threadId: string;
  snippet?: string;
};

function createOAuth2Client(clientId: string, clientSecret: string): OAuth2Client {
  // Redirect URI is not needed when using refresh token in server-to-server
  const oAuth2Client = new google.auth.OAuth2(clientId, clientSecret);
  return oAuth2Client;
}

export async function getGmailClient() {
  const config = getConfig();
  if (!config.GMAIL_CLIENT_ID || !config.GMAIL_CLIENT_SECRET || !config.GMAIL_REFRESH_TOKEN) {
    throw new Error("Missing Gmail credentials in environment variables");
  }
  const oAuth2Client = createOAuth2Client(config.GMAIL_CLIENT_ID, config.GMAIL_CLIENT_SECRET);
  oAuth2Client.setCredentials({ refresh_token: config.GMAIL_REFRESH_TOKEN });
  const gmail = google.gmail({ version: "v1", auth: oAuth2Client });
  return gmail;
}

export async function listUnreadLimited(maxResults: number): Promise<GmailMessage[]> {
  const gmail = await getGmailClient();
  const q = "label:INBOX label:UNREAD -category:promotions -category:social";
  const res = await gmail.users.messages.list({ userId: "me", q, maxResults });
  const messages = res.data.messages || [];
  return messages.map((m) => ({ id: m.id!, threadId: m.threadId! }));
}

export async function getMessageFull(messageId: string) {
  const gmail = await getGmailClient();
  const res = await gmail.users.messages.get({ userId: "me", id: messageId, format: "full" });
  return res.data;
}

function decodeBase64Url(data: string): string {
  const buff = Buffer.from(data.replace(/-/g, "+").replace(/_/g, "/"), "base64");
  return buff.toString("utf-8");
}

export function extractPlainTextFromMessage(message: any): { subject: string; from: string; to?: string; bodyText: string; snippet?: string; messageIdHeader?: string } {
  const headers = Object.fromEntries((message.payload?.headers || []).map((h: any) => [h.name.toLowerCase(), h.value]));
  const subject = headers["subject"] || "";
  const from = headers["from"] || "";
  const to = headers["to"];
  const messageIdHeader = headers["message-id"];

  let bodyText = "";
  const parts = message.payload?.parts;
  if (parts && Array.isArray(parts)) {
    const plainPart = parts.find((p: any) => p.mimeType === "text/plain") || parts.find((p: any) => p.mimeType?.startsWith("multipart"));
    if (plainPart?.body?.data) {
      bodyText = decodeBase64Url(plainPart.body.data);
    } else if (plainPart?.parts) {
      const nestedPlain = plainPart.parts.find((p: any) => p.mimeType === "text/plain");
      if (nestedPlain?.body?.data) bodyText = decodeBase64Url(nestedPlain.body.data);
    }
  } else if (message.payload?.body?.data) {
    bodyText = decodeBase64Url(message.payload.body.data);
  }

  return { subject, from, to, bodyText, snippet: message.snippet, messageIdHeader };
}

export async function sendReply({ threadId, to, subject, body, inReplyTo }: { threadId: string; to: string; subject: string; body: string; inReplyTo?: string; }) {
  const gmail = await getGmailClient();
  const replySubject = subject.startsWith("Re:") ? subject : `Re: ${subject}`;

  const raw = [
    `To: ${to}`,
    `Subject: ${replySubject}`,
    ...(inReplyTo ? [`In-Reply-To: ${inReplyTo}`, `References: ${inReplyTo}`] : []),
    `Content-Type: text/plain; charset=utf-8`,
    "",
    body,
  ].join("\r\n");
  const encoded = Buffer.from(raw).toString("base64").replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

  await gmail.users.messages.send({
    userId: "me",
    requestBody: {
      raw: encoded,
      threadId,
    },
  });
}

async function ensureLabelIdByName(name: string): Promise<string> {
  const gmail = await getGmailClient();
  const list = await gmail.users.labels.list({ userId: "me" });
  const found = (list.data.labels || []).find(l => l.name === name);
  if (found?.id) return found.id;
  const created = await gmail.users.labels.create({ userId: "me", requestBody: { name, labelListVisibility: "labelShow", messageListVisibility: "show" } });
  if (!created.data.id) throw new Error("Failed to create label");
  return created.data.id;
}

export async function markRepliedAndLabel({ messageId, addLabel, removeUnread = true }: { messageId: string; addLabel: string; removeUnread?: boolean; }) {
  const gmail = await getGmailClient();
  const labelsToAdd: string[] = [];
  const labelsToRemove: string[] = [];
  if (addLabel) {
    const id = await ensureLabelIdByName(addLabel);
    labelsToAdd.push(id);
  }
  if (removeUnread) labelsToRemove.push("UNREAD");
  await gmail.users.messages.modify({ userId: "me", id: messageId, requestBody: { addLabelIds: labelsToAdd, removeLabelIds: labelsToRemove } });
}

