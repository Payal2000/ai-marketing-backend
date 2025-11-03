// Simple config loader from environment variables
export function getConfig() {
  return {
    // Gmail OAuth
    GMAIL_CLIENT_ID: process.env.GMAIL_CLIENT_ID || "",
    GMAIL_CLIENT_SECRET: process.env.GMAIL_CLIENT_SECRET || "",
    GMAIL_REFRESH_TOKEN: process.env.GMAIL_REFRESH_TOKEN || "",
    
    // OpenAI
    OPENAI_API_KEY: process.env.OPENAI_API_KEY || "",
    
    // Supabase Database
    SUPABASE_DB_URL: process.env.SUPABASE_DB_URL || "",
    
    // App config
    BATCH_SIZE: Number(process.env.BATCH_SIZE || "5"),
    GMAIL_LABEL_INBOX: process.env.GMAIL_LABEL_INBOX || "ai-mvp",
    GMAIL_LABEL_REPLIED: process.env.GMAIL_LABEL_REPLIED || "AI_PROCESSED",
  };
}

export function getEnvConfig() {
  const config = getConfig();
  return {
    batchSize: config.BATCH_SIZE,
    gmailLabelInbox: config.GMAIL_LABEL_INBOX,
    gmailLabelReplied: config.GMAIL_LABEL_REPLIED,
  };
}

