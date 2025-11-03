import { Pool } from "pg";
import { getConfig } from "../utils/config";

let pool: Pool | null = null;

async function getPool(): Promise<Pool> {
  if (pool) return pool;
  const config = getConfig();
  if (!config.SUPABASE_DB_URL) {
    throw new Error("Missing SUPABASE_DB_URL environment variable");
  }
  pool = new Pool({ 
    connectionString: config.SUPABASE_DB_URL, 
    max: 3,
    ssl: {
      rejectUnauthorized: false // Supabase uses self-signed certificates
    }
  });
  return pool;
}

export type EmailRow = {
  id: string;
  gmail_message_id: string;
  gmail_thread_id: string;
  from_address: string;
  to_address: string | null;
  subject: string | null;
  snippet: string | null;
  body_text: string | null;
  received_at: string;
  reply_sent_at: string | null;
  status: string;
};

export async function upsertEmail(params: {
  gmail_message_id: string;
  gmail_thread_id: string;
  from_address: string;
  to_address?: string;
  subject?: string;
  snippet?: string;
  body_text?: string;
}): Promise<EmailRow> {
  const p = await getPool();
  const { rows } = await p.query(
    `insert into emails (gmail_message_id, gmail_thread_id, from_address, to_address, subject, snippet, body_text)
     values ($1,$2,$3,$4,$5,$6,$7)
     on conflict (gmail_message_id) do update set subject = EXCLUDED.subject
     returning *`,
    [
      params.gmail_message_id,
      params.gmail_thread_id,
      params.from_address,
      params.to_address || null,
      params.subject || null,
      params.snippet || null,
      params.body_text || null,
    ]
  );
  return rows[0] as EmailRow;
}

export async function upsertEmbedding(emailId: string, embedding: number[]) {
  const p = await getPool();
  await p.query(
    `insert into email_embeddings (email_id, embedding) values ($1, $2)
     on conflict (email_id) do update set embedding = EXCLUDED.embedding`,
    [emailId, embedding]
  );
}

export type SearchHit = { id: string; subject: string | null; body_text: string | null; similarity: number };

export async function searchSimilar(embedding: number[], limit: number): Promise<SearchHit[]> {
  const p = await getPool();
  const { rows } = await p.query(
    `select e.id, e.subject, e.body_text,
            1 - (ee.embedding <=> $1) as similarity
     from email_embeddings ee
     join emails e on e.id = ee.email_id
     order by ee.embedding <-> $1
     limit $2`,
    [embedding, limit]
  );
  return rows as SearchHit[];
}

export async function recordReply(emailId: string, model: string, replyText: string, tokensPrompt?: number, tokensCompletion?: number) {
  const p = await getPool();
  await p.query(
    `insert into email_replies (email_id, model, reply_text, tokens_prompt, tokens_completion)
     values ($1,$2,$3,$4,$5)`,
    [emailId, model, replyText, tokensPrompt || null, tokensCompletion || null]
  );
  await p.query(`update emails set reply_sent_at = now(), status = 'processed' where id = $1`, [emailId]);
}


