-- Enable pgcrypto for gen_random_uuid (Supabase often has it enabled)
create extension if not exists pgcrypto;
-- Enable pgvector
create extension if not exists vector;

-- Emails stored once per Gmail message
create table if not exists emails (
  id uuid primary key default gen_random_uuid(),
  gmail_message_id text not null unique,
  gmail_thread_id text not null,
  from_address text not null,
  to_address text,
  subject text,
  snippet text,
  body_text text,
  received_at timestamptz not null default now(),
  reply_sent_at timestamptz,
  status text not null default 'new' -- new|processed|failed
);

-- Embeddings for RAG (use 1536 dims for text-embedding-3-small)
create table if not exists email_embeddings (
  email_id uuid primary key references emails(id) on delete cascade,
  embedding vector(1536) not null
);
create index if not exists email_embeddings_idx on email_embeddings using ivfflat (embedding vector_cosine_ops);

-- Store model outputs + usage
create table if not exists email_replies (
  id uuid primary key default gen_random_uuid(),
  email_id uuid not null references emails(id) on delete cascade,
  model text not null,
  reply_text text not null,
  tokens_prompt int,
  tokens_completion int,
  created_at timestamptz not null default now()
);

