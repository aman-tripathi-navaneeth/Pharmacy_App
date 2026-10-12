# Security notes

- Keep `MONGODB_URL` and all secrets in local environment variables or a managed secrets store. Never commit them.
- Create a dedicated MongoDB Atlas database user with the minimum privileges needed; do not use an Atlas account-owner credential in the app.
- Restrict Atlas network access to known development/deployment sources where practical. Avoid broad public access for production.
- Authenticate and authorize every store-scoped endpoint on the server. A `store_id` in a URL is not proof of access.
- Use synthetic test data. Do not put real prescription, customer, invoice, or patient information in tickets or screenshots.
- Log actor, time, source document, and reason for stock adjustments, without logging passwords, tokens, or unnecessary personal information.
- Report suspected credential exposure promptly, revoke/rotate the credential, and remove it from repository history where necessary.
