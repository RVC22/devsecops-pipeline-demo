const express = require('express');
const bodyParser = require('body-parser');
const sqlite3 = require('sqlite3').verbose();
const app = express();
app.use(bodyParser.json());

const DBFILE = './users.db';

const db = new sqlite3.Database(DBFILE);
db.serialize(() => {
  db.run("CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY, username TEXT, password TEXT)");
  db.run("INSERT OR IGNORE INTO users (id, username, password) VALUES (1,'alice','password123')");
});

app.get('/user', (req, res) => {
  const id = req.query.id || '1';
  const sql = `SELECT id, username FROM users WHERE id = ${id};`;
  db.all(sql, [], (err, rows) => {
    if (err) return res.status(500).send("DB error");
    res.json(rows);
  });
});

app.get('/greet', (req, res) => {
  const name = req.query.name || 'guest';
  res.send(`<h1>Hello ${name}</h1>`);
});

app.get('/', (req, res) => {
  res.send('<h2>DevSecOps Lab App</h2><p>Try /user?id=1 and /greet?name=xyz</p>');
});

const port = process.env.PORT || 3000;
app.listen(port, () => {
  console.log(`Vulnerable app listening on port ${port}`);
});
