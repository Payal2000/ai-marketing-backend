import { embedText } from "../clients/openai";
import { searchSimilar } from "../clients/db";

export async function retrieveContext(question: string, k: number = 5) {
  const embedding = await embedText(question);
  const hits = await searchSimilar(embedding, k);
  const context = hits
    .map((h, i) => `[#${i + 1} sim=${h.similarity.toFixed(3)}] subject: ${h.subject || "(no subject)"}\n${(h.body_text || "").slice(0, 1500)}`)
    .join("\n\n");
  return { embedding, context };
}

