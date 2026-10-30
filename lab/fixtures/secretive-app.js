// Dies with a credential in its stack trace, the way a real misconfigured app does.
// The alert carries a stderr excerpt, so this proves redaction happens before anything
// leaves the host.
console.error('[secretive-app] connecting with AKIAIOSFODNN7EXAMPLE');
console.error('[secretive-app] dsn=postgres://appuser:hunter2@db.internal:5432/main');
console.error('Error: ECONNREFUSED while authenticating');
setTimeout(() => process.exit(1), 400);
