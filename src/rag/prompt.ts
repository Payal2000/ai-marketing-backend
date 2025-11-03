export function buildPrompt({ question, context }: { question: string; context: string }) {
  return `You are an expert marketing analyst.

Context (may be incomplete):
${context}

Task: Answer the user's question using only the provided context. If the context is insufficient, say what is missing and ask up to 1 clarifying question. Be concise.

Question: ${question}`;
}

