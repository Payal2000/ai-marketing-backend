# Setup Guide

This project now uses `.env` files instead of AWS Secrets Manager for simplicity.

## 1. Install Dependencies

```bash
npm install
```

## 2. Configure Environment Variables

Copy the example file and fill in your values:

```bash
cp .env.example .env
```

Edit `.env` and add your credentials:

```env
# Gmail OAuth Credentials
GMAIL_CLIENT_ID=your-gmail-client-id
GMAIL_CLIENT_SECRET=your-gmail-client-secret
GMAIL_REFRESH_TOKEN=your-gmail-refresh-token

# OpenAI API Key
OPENAI_API_KEY=sk-your-openai-api-key

# Supabase Database Connection
SUPABASE_DB_URL=postgresql://postgres:password@host:5432/postgres?sslmode=require

# App Configuration (optional)
BATCH_SIZE=5
GMAIL_LABEL_INBOX=ai-mvp
GMAIL_LABEL_REPLIED=AI_PROCESSED
```

## 3. Test Database Connection

Test your Supabase connection:

```bash
npm run test:db
```

This will verify:
- Database connection works
- Shows database version and name
- Lists existing tables

## 4. Set Up Supabase Schema

Run the e-commerce schema in your Supabase SQL Editor:

1. Open Supabase Dashboard → SQL Editor
2. Copy and paste contents of `db/ecommerce_schema.sql`
3. Click "Run"
4. Verify tables were created

## 5. Local Testing

Run the Lambda function locally:

```bash
npm run start:local
```

This will:
- Load environment variables from `.env`
- Poll Gmail for new messages
- Process and reply to emails

## 6. Deploy to AWS Lambda

When deploying to AWS, set environment variables:

```bash
export GMAIL_CLIENT_ID=your-id
export GMAIL_CLIENT_SECRET=your-secret
export GMAIL_REFRESH_TOKEN=your-token
export OPENAI_API_KEY=sk-...
export SUPABASE_DB_URL=postgresql://...

npm run deploy
```

Or use a `.env` file with serverless-dotenv-plugin (optional).

## Notes

- The `.env` file is gitignored - never commit secrets
- For AWS deployment, env vars are passed via `serverless.yml`
- All credentials are read from environment variables

