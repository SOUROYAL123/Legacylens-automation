const express = require('express');
const { Pool } = require('pg');

const app = express();
const port = process.env.PORT || 3000;

// PostgreSQL connection pool utilizing ECS environment variables
const pool = new Pool({
  host: process.env.DB_HOST,
  port: process.env.DB_PORT || 5432,
  database: process.env.DB_NAME || 'legacylens_prod',
  user: process.env.DB_USER || 'postgres',
  password: process.env.DB_PASSWORD,
});

app.use(express.json());

// Health check endpoint required for target group validation
app.get('/health', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    res.status(200).json({ status: 'healthy', database: 'connected' });
  } catch (err) {
    console.error('Database connection error:', err.message);
    res.status(500).json({ status: 'unhealthy', error: err.message });
  }
});

// WhatsApp webhook endpoint placeholder
app.post('/webhook', (req, res) => {
  console.log('Received WhatsApp message payload:', req.body);
  res.status(200).send('EVENT_RECEIVED');
});

app.listen(port, () => {
  console.log(`Legacylens bot server is running on port ${port}`);
});