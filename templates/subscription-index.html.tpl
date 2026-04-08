<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>{{ user.username }} | Subscription</title>
  <style>
    :root {
      --bg: #edf3f6;
      --card: rgba(255, 255, 255, 0.92);
      --ink: #0f172a;
      --muted: #526072;
      --line: rgba(15, 23, 42, 0.08);
      --accent: #0f766e;
      --accent-dark: #115e59;
      --accent-soft: rgba(15, 118, 110, 0.1);
      --danger: #b91c1c;
      --warn: #b45309;
      --disabled: #64748b;
      --shadow: 0 26px 60px rgba(15, 23, 42, 0.14);
    }

    * {
      box-sizing: border-box;
    }

    body {
      margin: 0;
      color: var(--ink);
      font-family: "Segoe UI", "SF Pro Display", system-ui, sans-serif;
      background:
        radial-gradient(circle at top left, rgba(14, 165, 233, 0.16), transparent 24%),
        radial-gradient(circle at bottom right, rgba(20, 184, 166, 0.14), transparent 28%),
        linear-gradient(180deg, #f7fbfc 0%, var(--bg) 100%);
      min-height: 100vh;
    }

    .shell {
      width: min(1040px, calc(100vw - 28px));
      margin: 0 auto;
      padding: 28px 0 40px;
    }

    .hero,
    .panel,
    .link-card,
    .qr-modal {
      background: var(--card);
      border: 1px solid var(--line);
      box-shadow: var(--shadow);
      backdrop-filter: blur(14px);
    }

    .hero {
      border-radius: 28px;
      padding: 28px;
      margin-bottom: 18px;
      overflow: hidden;
      position: relative;
    }

    .hero::after {
      content: "";
      position: absolute;
      inset: auto -40px -70px auto;
      width: 200px;
      height: 200px;
      border-radius: 50%;
      background: radial-gradient(circle, rgba(15, 118, 110, 0.18), transparent 65%);
      pointer-events: none;
    }

    .eyebrow {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      border-radius: 999px;
      padding: 8px 12px;
      background: rgba(255, 255, 255, 0.74);
      color: var(--muted);
      font-size: 13px;
      margin-bottom: 16px;
    }

    h1 {
      margin: 0 0 10px;
      font-size: clamp(30px, 4vw, 46px);
      line-height: 1.05;
      letter-spacing: -0.03em;
    }

    .subtext {
      margin: 0;
      max-width: 720px;
      color: var(--muted);
      line-height: 1.65;
      font-size: 15px;
    }

    .hero-actions {
      display: flex;
      flex-wrap: wrap;
      gap: 10px;
      margin-top: 18px;
    }

    .status {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      padding: 8px 12px;
      border-radius: 999px;
      font-size: 13px;
      font-weight: 700;
      letter-spacing: 0.02em;
      text-transform: uppercase;
    }

    .status.active {
      background: rgba(22, 163, 74, 0.12);
      color: #166534;
    }

    .status.limited {
      background: rgba(185, 28, 28, 0.1);
      color: var(--danger);
    }

    .status.expired {
      background: rgba(180, 83, 9, 0.12);
      color: var(--warn);
    }

    .status.disabled {
      background: rgba(100, 116, 139, 0.12);
      color: var(--disabled);
    }

    .grid {
      display: grid;
      grid-template-columns: minmax(280px, 340px) 1fr;
      gap: 18px;
    }

    .panel {
      border-radius: 24px;
      padding: 22px;
    }

    .panel h2 {
      margin: 0 0 16px;
      font-size: 18px;
    }

    .meta-list {
      display: grid;
      gap: 12px;
    }

    .meta-item {
      padding: 14px;
      border: 1px solid var(--line);
      border-radius: 18px;
      background: rgba(255, 255, 255, 0.72);
    }

    .meta-label {
      margin-bottom: 6px;
      color: var(--muted);
      font-size: 12px;
      letter-spacing: 0.04em;
      text-transform: uppercase;
    }

    .meta-value {
      font-size: 16px;
      font-weight: 600;
      word-break: break-word;
    }

    .links {
      display: grid;
      gap: 14px;
    }

    .quick-actions {
      display: grid;
      gap: 12px;
      margin-top: 18px;
    }

    .link-card {
      border-radius: 24px;
      padding: 18px;
    }

    .link-head {
      display: flex;
      justify-content: space-between;
      gap: 14px;
      align-items: center;
      margin-bottom: 12px;
    }

    .link-title {
      font-size: 17px;
      font-weight: 700;
    }

    .link-index {
      color: var(--muted);
      font-size: 13px;
    }

    textarea {
      width: 100%;
      min-height: 110px;
      resize: vertical;
      border: 1px solid var(--line);
      border-radius: 18px;
      padding: 14px;
      background: rgba(248, 250, 252, 0.9);
      color: var(--ink);
      font: 13px/1.5 "SFMono-Regular", Consolas, monospace;
    }

    .actions {
      display: flex;
      flex-wrap: wrap;
      gap: 10px;
      margin-top: 14px;
    }

    button {
      appearance: none;
      border: 0;
      border-radius: 999px;
      padding: 11px 15px;
      cursor: pointer;
      font-size: 14px;
      font-weight: 600;
      transition: transform 120ms ease, opacity 120ms ease;
    }

    button:hover {
      transform: translateY(-1px);
    }

    .primary {
      color: #fff;
      background: linear-gradient(135deg, var(--accent), var(--accent-dark));
    }

    .secondary {
      color: var(--ink);
      background: #fff;
      border: 1px solid var(--line);
    }

    .empty {
      padding: 28px;
      border-radius: 24px;
      border: 1px dashed rgba(15, 23, 42, 0.18);
      background: rgba(255, 255, 255, 0.7);
      color: var(--muted);
      line-height: 1.65;
      text-align: center;
    }

    .qr-backdrop {
      position: fixed;
      inset: 0;
      display: none;
      place-items: center;
      background: rgba(15, 23, 42, 0.5);
      padding: 18px;
      z-index: 9999;
    }

    .qr-modal {
      width: min(420px, calc(100vw - 32px));
      border-radius: 26px;
      padding: 20px;
      text-align: center;
    }

    .qr-header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 16px;
      text-align: left;
    }

    .qr-header h3 {
      margin: 0;
      font-size: 18px;
    }

    .qr-header p {
      margin: 4px 0 0;
      color: var(--muted);
      font-size: 13px;
    }

    .icon-button {
      padding: 10px 12px;
      border-radius: 999px;
      color: var(--ink);
      background: #fff;
      border: 1px solid var(--line);
    }

    #qrCodeContainer {
      display: grid;
      place-items: center;
      min-height: 272px;
      padding: 12px;
      border-radius: 20px;
      background: linear-gradient(180deg, rgba(255,255,255,0.95), rgba(241,245,249,0.92));
      border: 1px solid var(--line);
    }

    .helper-text {
      color: var(--muted);
      font-size: 13px;
      line-height: 1.6;
      margin: 0;
    }

    .client-grid {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 10px;
    }

    .client-chip {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      text-align: center;
      min-height: 46px;
      padding: 10px 12px;
      border-radius: 16px;
      border: 1px solid var(--line);
      background: rgba(255, 255, 255, 0.8);
      color: var(--ink);
      font-size: 13px;
      font-weight: 600;
    }

    @media (max-width: 860px) {
      .grid {
        grid-template-columns: 1fr;
      }

      .shell {
        width: min(100vw - 18px, 1040px);
        padding-top: 18px;
      }

      .hero,
      .panel,
      .link-card {
        border-radius: 20px;
      }

      .client-grid {
        grid-template-columns: 1fr;
      }
    }
  </style>
  <script src="https://cdnjs.cloudflare.com/ajax/libs/qrcodejs/1.0.0/qrcode.min.js"></script>
</head>
<body>
  <main class="shell">
    <section class="hero">
      <div class="eyebrow">Subscription access</div>
      <h1>{{ user.username }}</h1>
      <p class="subtext">Manage your connection links, copy them into clients, or open a QR code for quick import.</p>
      <div class="hero-actions">
        <button class="primary" onclick="copyCurrentPage(this)">Copy Subscription URL</button>
        <button class="secondary" onclick="openSubscriptionQr()">Subscription QR</button>
      </div>
    </section>

    <section class="grid">
      <aside class="panel">
        <h2>Profile Overview</h2>
        <div class="meta-list">
          <article class="meta-item">
            <div class="meta-label">Status</div>
            <div class="meta-value">
              <span class="status {% if user.status.value == 'active' %}active{% elif user.status.value == 'limited' %}limited{% elif user.status.value == 'expired' %}expired{% elif user.status.value == 'disabled' %}disabled{% endif %}">
                {{ user.status.value }}
              </span>
            </div>
          </article>
          <article class="meta-item">
            <div class="meta-label">Data Limit</div>
            <div class="meta-value">{% if not user.data_limit %}Unlimited{% else %}{{ user.data_limit | bytesformat }}{% endif %}</div>
          </article>
          <article class="meta-item">
            <div class="meta-label">Data Used</div>
            <div class="meta-value">
              {{ user.used_traffic | bytesformat }}
              {% if user.data_limit_reset_strategy != 'no_reset' %}
              <br><span style="font-size:13px;color:var(--muted);font-weight:500;">resets every {{ user.data_limit_reset_strategy.value }}</span>
              {% endif %}
            </div>
          </article>
          <article class="meta-item">
            <div class="meta-label">Expiration</div>
            <div class="meta-value">
              {% if not user.expire %}
              Unlimited
              {% else %}
              {% set current_timestamp = now().timestamp() %}
              {% set remaining_days = ((user.expire - current_timestamp) // (24 * 3600)) %}
              {{ user.expire | datetime }}
              <br><span style="font-size:13px;color:var(--muted);font-weight:500;">{{ remaining_days | int }} days remaining</span>
              {% endif %}
            </div>
          </article>
        </div>

        <div class="quick-actions">
          <article class="meta-item">
            <div class="meta-label">Client Setup</div>
            <p class="helper-text">Use the subscription URL in your preferred client or copy one of the direct links from the right.</p>
            <div class="client-grid">
              <div class="client-chip">v2rayN</div>
              <div class="client-chip">v2rayNG</div>
              <div class="client-chip">Hiddify</div>
              <div class="client-chip">Streisand</div>
            </div>
          </article>
          <article class="meta-item">
            <div class="meta-label">Tips</div>
            <p class="helper-text">If one client import fails, copy a direct connection link and import it manually. The subscription URL itself is often the easiest option for everyday sync.</p>
          </article>
        </div>
      </aside>

      <section class="links">
        {% if user.status == 'active' and user.links %}
        {% for link in user.links %}
        <article class="link-card">
          <div class="link-head">
            <div>
              <div class="link-title">Connection Link</div>
              <div class="link-index">Profile {{ loop.index }}</div>
            </div>
          </div>
          <textarea readonly>{{ link }}</textarea>
          <div class="actions">
            <button class="primary" onclick="copyLink(this)">Copy Link</button>
            <button class="secondary" data-link="{{ link | e }}" onclick="openQr(this)">Show QR</button>
          </div>
        </article>
        {% endfor %}
        {% else %}
        <div class="empty">
          Active links are not available for this account right now. Check account status or data limits in the panel.
        </div>
        {% endif %}
      </section>
    </section>
  </main>

  <div class="qr-backdrop" id="qrBackdrop">
    <div class="qr-modal">
      <div class="qr-header">
        <div>
          <h3>QR Code</h3>
          <p>Scan in your client app to import the link.</p>
        </div>
        <button class="icon-button" onclick="closeQr()">Close</button>
      </div>
      <div id="qrCodeContainer"></div>
    </div>
  </div>

  <script>
    function safeWriteClipboard(text) {
      if (navigator.clipboard && window.isSecureContext) {
        return navigator.clipboard.writeText(text);
      }

      return new Promise(function (resolve, reject) {
        const tempInput = document.createElement('textarea');
        tempInput.value = text;
        tempInput.style.position = 'fixed';
        tempInput.style.opacity = '0';
        document.body.appendChild(tempInput);
        tempInput.focus();
        tempInput.select();

        try {
          document.execCommand('copy');
          document.body.removeChild(tempInput);
          resolve();
        } catch (error) {
          document.body.removeChild(tempInput);
          reject(error);
        }
      });
    }

    function copyLink(button) {
      const textarea = button.closest('.link-card').querySelector('textarea');
      safeWriteClipboard(textarea.value).then(() => {
        const original = button.textContent;
        button.textContent = 'Copied';
        setTimeout(() => {
          button.textContent = original;
        }, 1400);
      });
    }

    let qrCode;

    function openQr(button) {
      const link = button.getAttribute('data-link');
      const backdrop = document.getElementById('qrBackdrop');
      const container = document.getElementById('qrCodeContainer');

      container.innerHTML = '';
      qrCode = new QRCode(container, {
        text: link,
        width: 256,
        height: 256,
        correctLevel: QRCode.CorrectLevel.M
      });

      backdrop.style.display = 'grid';
    }

    function copyCurrentPage(button) {
      safeWriteClipboard(window.location.href).then(() => {
        const original = button.textContent;
        button.textContent = 'Copied';
        setTimeout(() => {
          button.textContent = original;
        }, 1400);
      });
    }

    function openSubscriptionQr() {
      const backdrop = document.getElementById('qrBackdrop');
      const container = document.getElementById('qrCodeContainer');

      container.innerHTML = '';
      qrCode = new QRCode(container, {
        text: window.location.href,
        width: 256,
        height: 256,
        correctLevel: QRCode.CorrectLevel.M
      });

      backdrop.style.display = 'grid';
    }

    function closeQr() {
      document.getElementById('qrBackdrop').style.display = 'none';
      document.getElementById('qrCodeContainer').innerHTML = '';
    }

    document.getElementById('qrBackdrop').addEventListener('click', function (event) {
      if (event.target === this) {
        closeQr();
      }
    });
  </script>
</body>
</html>
