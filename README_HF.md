
# Multi-Agent Analytics System

Multi-agent AI system for querying Google Analytics 4 and SEO data using natural language.

## API Endpoints

- **POST /query** - Submit natural language analytics queries
- **GET /health** - Health check endpoint
- **GET /docs** - Interactive API documentation

## Configuration

Set the following secrets in your Hugging Face Space settings:

| Secret | Description |
|--------|-------------|
| `OPENAI_API_KEY` | Your OpenAI API key |
| `GA4_PROPERTY_ID` | Google Analytics 4 property ID |
| `SHEET_ID` | Google Sheets ID for SEO data |
| `GOOGLE_CREDENTIALS_JSON` | Base64 encoded Google credentials |

## Usage

```bash
curl -X POST https://your-space.hf.space/query \
  -H "Content-Type: application/json" \
  -d '{"query": "What are my top pages this week?"}'
```
