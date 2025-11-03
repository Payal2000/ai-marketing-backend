import OpenAI from "openai";
import { getConfig } from "../utils/config";

let client: OpenAI | null = null;

export async function getOpenAI() {
  if (client) return client;
  const config = getConfig();
  if (!config.OPENAI_API_KEY) {
    throw new Error("Missing OPENAI_API_KEY environment variable");
  }
  client = new OpenAI({ apiKey: config.OPENAI_API_KEY });
  return client;
}

export async function embedText(text: string): Promise<number[]> {
  const c = await getOpenAI();
  const res = await c.embeddings.create({ model: "text-embedding-3-small", input: text });
  return res.data[0].embedding as unknown as number[];
}

export async function generateInsight(prompt: string): Promise<{ text: string; model: string; usage?: { prompt_tokens?: number; completion_tokens?: number } }> {
  const c = await getOpenAI();
  const chat = await c.chat.completions.create({
    model: "gpt-4o-mini",
    messages: [
      { role: "system", content: "You are an analyst. Answer concisely with clear bullets when appropriate. If unsure, ask for clarification succinctly." },
      { role: "user", content: prompt },
    ],
    temperature: 0.2,
    max_tokens: 500,
  });
  const choice = chat.choices[0];
  return { text: choice.message?.content || "", model: chat.model || "gpt-4o-mini", usage: chat.usage };
}

