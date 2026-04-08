<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Silentbridge Workspace</title>
  <style>
    body {
      margin: 0;
      min-height: 100vh;
      display: grid;
      place-items: center;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background:
        radial-gradient(circle at top left, rgba(14, 165, 233, 0.18), transparent 28%),
        radial-gradient(circle at bottom right, rgba(16, 185, 129, 0.14), transparent 30%),
        #eef4f7;
      color: #0f172a;
    }

    .card {
      width: min(560px, calc(100vw - 32px));
      padding: 32px;
      border-radius: 24px;
      background: rgba(255, 255, 255, 0.92);
      border: 1px solid rgba(15, 23, 42, 0.08);
      box-shadow: 0 24px 48px rgba(15, 23, 42, 0.12);
    }

    h1 {
      margin: 0 0 12px;
      font-size: 30px;
    }

    p {
      margin: 0;
      line-height: 1.6;
      color: #475569;
    }
  </style>
</head>
<body>
  <main class="card">
    <h1>Silentbridge Workspace</h1>
    <p>This endpoint is available and serving TLS correctly. Access is managed internally.</p>
  </main>
</body>
</html>
