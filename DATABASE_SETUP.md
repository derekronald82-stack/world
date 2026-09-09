# CATWS SONGS database setup

Production uses PostgreSQL through SQLAlchemy. Set `DATABASE_URL` to a
`postgresql+psycopg://...` URL and run:

```powershell
cd backend
alembic upgrade head
```

The additive migration creates an empty database from the ORM metadata and
adds missing v6 columns to an existing database. It never drops or resets
catalog rows. SQLite is supported only for local development and tests; the
production startup check rejects SQLite or a missing database URL.
