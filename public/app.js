(() => {
  "use strict";

  // Endpoint is relative to this page, so it works whether the site is served
  // at http://localhost:8000/ or from a subfolder on shared hosting.
  // If the frontend is ever hosted on a DIFFERENT origin than the backend,
  // change this to the absolute URL and add that origin to `allowed_origins`
  // in private/config.php.
  const API_URL = "api/chat.php";
  const SESSION_KEY = "dialogflow_session_id";

  const messagesEl = document.getElementById("messages");
  const formEl = document.getElementById("chat-form");
  const inputEl = document.getElementById("chat-input");
  const sendBtn = document.getElementById("send-btn");
  const newChatBtn = document.getElementById("new-chat");

  // --- session management --------------------------------------------------
  function getSessionId() {
    let id = localStorage.getItem(SESSION_KEY);
    if (!id) {
      id = (crypto.randomUUID && crypto.randomUUID()) ||
           String(Date.now()) + "-" + Math.random().toString(16).slice(2);
      localStorage.setItem(SESSION_KEY, id);
    }
    return id;
  }

  function resetSession() {
    localStorage.removeItem(SESSION_KEY);
    messagesEl.innerHTML = "";
    getSessionId(); // create a fresh one immediately
    addMessage("agent", "Started a new conversation. How can I help?");
    inputEl.focus();
  }

  // --- rendering (always uses textContent -> no HTML injection) ------------
  function addMessage(role, text) {
    const el = document.createElement("div");
    el.className = "msg msg--" + role;
    el.textContent = text;
    messagesEl.appendChild(el);
    messagesEl.scrollTop = messagesEl.scrollHeight;
    return el;
  }

  function showTyping() {
    const el = document.createElement("div");
    el.className = "msg msg--agent msg--typing";
    el.innerHTML = "<span></span><span></span><span></span>";
    messagesEl.appendChild(el);
    messagesEl.scrollTop = messagesEl.scrollHeight;
    return el;
  }

  function setBusy(busy) {
    inputEl.disabled = busy;
    sendBtn.disabled = busy;
    if (!busy) inputEl.focus();
  }

  // --- send flow -----------------------------------------------------------
  async function sendMessage(message) {
    addMessage("user", message);
    setBusy(true);
    const typingEl = showTyping();

    try {
      const res = await fetch(API_URL, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ message, session_id: getSessionId() }),
      });

      const data = await res.json().catch(() => ({}));
      typingEl.remove();

      if (!res.ok || data.error) {
        addMessage("error", data.error || ("Request failed (" + res.status + ")."));
        return;
      }
      addMessage("agent", data.reply || "(no response)");
    } catch (err) {
      typingEl.remove();
      addMessage("error", "Network error — is the local server running?");
    } finally {
      setBusy(false);
    }
  }

  // --- wiring --------------------------------------------------------------
  formEl.addEventListener("submit", (e) => {
    e.preventDefault();
    const message = inputEl.value.trim();
    if (!message) return;
    inputEl.value = "";
    sendMessage(message);
  });

  newChatBtn.addEventListener("click", resetSession);

  // Initialize on load.
  getSessionId();
  addMessage("agent", "Hi! Ask me anything.");
  inputEl.focus();
})();
