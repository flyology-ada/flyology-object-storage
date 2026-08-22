(() => {
  "use strict";

  const loginShell = document.querySelector("#login-shell");
  const loginForm = document.querySelector("#login-form");
  const loginMessage = document.querySelector("#login-message");
  const workbench = document.querySelector("#workbench");
  const connectionState = document.querySelector("#connection-state");
  const refreshButton = document.querySelector("#refresh");
  const logoutButton = document.querySelector("#logout");
  const copyEndpoint = document.querySelector("#copy-endpoint");
  const toast = document.querySelector("#toast");
  let pollTimer;
  let toastTimer;

  const backendCopy = {
    memory: "Objects live in a bounded in-process store. Restarting the server clears this backend.",
    files: "Opaque object paths publish atomically beneath the configured local storage root.",
    sqlite: "SQLite owns the transactional namespace while immutable payload files carry object data."
  };

  function setConnection(kind, label) {
    connectionState.dataset.state = kind;
    connectionState.querySelector("span:last-child").textContent = label;
  }

  function showToast(message) {
    clearTimeout(toastTimer);
    toast.textContent = message;
    toast.hidden = false;
    toastTimer = setTimeout(() => { toast.hidden = true; }, 2400);
  }

  function showLogin(message = "") {
    clearTimeout(pollTimer);
    workbench.hidden = true;
    loginShell.hidden = false;
    loginMessage.textContent = message;
    setConnection("locked", "Administrator sign-in required");
    const password = loginForm.elements.password;
    password.value = "";
    password.focus();
  }

  function renderStatus(status) {
    const endpoint = `http://${status.s3_address}:${status.s3_port}`;
    loginShell.hidden = true;
    workbench.hidden = false;
    document.querySelector("#s3-endpoint").textContent = endpoint;
    document.querySelector("#backend").textContent = status.backend;
    document.querySelector("#region").textContent = status.region;
    document.querySelector("#s3-service-detail").textContent = `${endpoint} · ready`;
    document.querySelector("#admin-service-detail").textContent = `${location.origin} · ready`;
    document.querySelector("#backend-summary").textContent = backendCopy[status.backend] || "Backend active.";
    document.querySelectorAll("[data-backend]").forEach(item => {
      item.dataset.active = String(item.dataset.backend === status.backend);
    });
    document.querySelector("#last-updated").textContent =
      `Runtime checked ${new Intl.DateTimeFormat(undefined, { timeStyle: "medium" }).format(new Date())}`;
    setConnection("ready", `${status.backend} backend ready`);
    clearTimeout(pollTimer);
    pollTimer = setTimeout(() => refreshStatus(true), 5000);
  }

  async function refreshStatus(quiet = false) {
    if (!quiet) {
      refreshButton.disabled = true;
      setConnection("checking", "Refreshing runtime");
    }
    try {
      const response = await fetch("/api/status", {
        credentials: "same-origin",
        headers: { Accept: "application/json" }
      });
      if (response.status === 401) {
        showLogin(quiet ? "Your session ended. Sign in again." : "");
        return;
      }
      if (!response.ok) throw new Error(`status ${response.status}`);
      renderStatus(await response.json());
    } catch (_error) {
      clearTimeout(pollTimer);
      setConnection("error", "Server unavailable");
      if (workbench.hidden) {
        showLogin("The management service is unavailable. Try again shortly.");
        setConnection("error", "Server unavailable");
      }
      else pollTimer = setTimeout(() => refreshStatus(true), 5000);
    } finally {
      refreshButton.disabled = false;
    }
  }

  loginForm.addEventListener("submit", async event => {
    event.preventDefault();
    const submit = loginForm.querySelector("button[type=submit]");
    const password = loginForm.elements.password.value;
    loginMessage.textContent = "";
    submit.disabled = true;
    submit.textContent = "Signing in…";
    setConnection("checking", "Verifying credential");
    try {
      const response = await fetch("/api/login", {
        method: "POST",
        credentials: "same-origin",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: `username=admin&password=${password}`
      });
      if (response.status === 401) {
        showLogin("That credential was not accepted. Check the first-start server output.");
        return;
      }
      if (!response.ok) throw new Error(`login ${response.status}`);
      loginForm.elements.password.value = "";
      await refreshStatus();
    } catch (_error) {
      showLogin("Sign-in could not reach the management service. Try again.");
    } finally {
      submit.disabled = false;
      submit.textContent = "Sign in";
    }
  });

  refreshButton.addEventListener("click", () => refreshStatus());

  logoutButton.addEventListener("click", async () => {
    logoutButton.disabled = true;
    try {
      const response = await fetch("/api/logout", {
        method: "POST",
        credentials: "same-origin"
      });
      if (!response.ok && response.status !== 401) {
        throw new Error(`logout ${response.status}`);
      }
      showLogin("Signed out.");
    } catch (_error) {
      showToast("Sign out failed. The current session is still active.");
      setConnection("error", "Sign out failed");
    } finally {
      logoutButton.disabled = false;
    }
  });

  copyEndpoint.addEventListener("click", async () => {
    const value = document.querySelector("#s3-endpoint").textContent;
    try {
      await navigator.clipboard.writeText(value);
      showToast("S3 endpoint copied");
    } catch (_error) {
      showToast("Clipboard access was unavailable");
    }
  });

  refreshStatus();
})();
