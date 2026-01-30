-- Required PostgreSQL extensions for the email automation system

-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Enable vector operations for embeddings (RAG)
CREATE EXTENSION IF NOT EXISTS "vector";

-- Enable fuzzy text search (optional but useful for email search)
CREATE EXTENSION IF NOT EXISTS "pg_trgm";
