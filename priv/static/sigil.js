/**
 * Sigil.js — ~2KB client runtime for Sigil.Live
 *
 * Opens a WebSocket to the server, joins the Live session,
 * captures DOM events, and applies server-sent patches.
 * Includes CSRF token in all messages for protection.
 */
(function() {
  "use strict";

  // Find the Live root element
  const root = document.querySelector("[data-sigil-session]");
  if (!root) return;

  const sessionId = root.dataset.sigilSession;
  const csrfToken = root.dataset.sigilCsrf ||
    document.querySelector('meta[name="sigil-csrf"]')?.content || "";
  const proto = location.protocol === "https:" ? "wss:" : "ws:";
  const wsUrl = `${proto}//${location.host}/__sigil/websocket`;

  let ws = null;
  let retries = 0;
  const MAX_RETRIES = 20;
  const BASE_DELAY = 500;

  function connect() {
    ws = new WebSocket(wsUrl);

    ws.onopen = function() {
      retries = 0;
      // Join the session with CSRF token
      ws.send(JSON.stringify({
        type: "join",
        session: sessionId,
        csrf: csrfToken
      }));
    };

    ws.onmessage = function(e) {
      let msg;
      try { msg = JSON.parse(e.data); } catch(_) { return; }

      if (msg.type === "patch") {
        applyPatches(msg.patches);
      } else if (msg.type === "error") {
        console.warn("[Sigil] Server error:", msg.reason);
        if (msg.reason === "csrf_failed") {
          // Don't retry on CSRF failure — requires page reload
          retries = MAX_RETRIES;
        }
      }
    };

    ws.onclose = function() {
      if (retries < MAX_RETRIES) {
        retries++;
        setTimeout(connect, Math.min(BASE_DELAY * Math.pow(2, retries - 1), 30000));
      }
    };

    ws.onerror = function() {
      ws.close();
    };
  }

  // --- Event binding ---

  // Delegate events from the root
  root.addEventListener("click", function(e) {
    const el = e.target.closest("[sigil-click]");
    if (el) {
      e.preventDefault();
      sendEvent(el.getAttribute("sigil-click"), getValues(el));
    }
  });

  root.addEventListener("submit", function(e) {
    const form = e.target.closest("[sigil-submit]");
    if (form) {
      e.preventDefault();
      const data = Object.fromEntries(new FormData(form));
      sendEvent(form.getAttribute("sigil-submit"), data);
    }
  });

  root.addEventListener("input", function(e) {
    const el = e.target.closest("[sigil-change]");
    if (el) {
      sendEvent(el.getAttribute("sigil-change"), { value: el.value });
    }
  });

  root.addEventListener("keydown", function(e) {
    const el = e.target.closest("[sigil-keydown]");
    if (el) {
      sendEvent(el.getAttribute("sigil-keydown"), { key: e.key, value: el.value });
    }
  });

  function sendEvent(event, value) {
    if (ws && ws.readyState === 1) {
      ws.send(JSON.stringify({ type: "event", event: event, value: value }));
    }
  }

  function getValues(el) {
    const v = {};
    if (el.dataset.sigilValue) {
      try { Object.assign(v, JSON.parse(el.dataset.sigilValue)); } catch(_) {}
    }
    if (el.value !== undefined) v.value = el.value;
    return v;
  }

  // --- Patch application ---

  function applyPatches(patches) {
    for (const p of patches) {
      try {
        switch (p.op) {
          case "replace_children": {
            const parent = resolveParent(root, p.path);
            if (parent) parent.innerHTML = p.html;
            break;
          }
          case "text": {
            const node = resolveNode(root, p.path);
            if (node) node.textContent = p.content;
            break;
          }
          case "replace": {
            const node = resolveNode(root, p.path);
            if (!node) break;
            if (node.nodeType === 1) {
              node.outerHTML = p.html;
            } else {
              const temp = document.createElement("div");
              temp.innerHTML = p.html;
              node.parentNode.replaceChild(temp.firstChild || document.createTextNode(""), node);
            }
            break;
          }
          case "insert": {
            const parent = resolveParent(root, p.path);
            if (parent) {
              const temp = document.createElement("div");
              temp.innerHTML = p.html;
              while (temp.firstChild) parent.appendChild(temp.firstChild);
            }
            break;
          }
          case "remove": {
            const node = resolveNode(root, p.path);
            if (node && node.parentNode) node.parentNode.removeChild(node);
            break;
          }
          case "attr": {
            const node = resolveNode(root, p.path);
            if (node && node.setAttribute) node.setAttribute(p.key, p.value);
            break;
          }
          case "remove_attr": {
            const node = resolveNode(root, p.path);
            if (node && node.removeAttribute) node.removeAttribute(p.key);
            break;
          }
        }
      } catch(err) {
        console.warn("[Sigil] Patch failed, path:", p.path, err);
      }
    }
  }

  function resolveNode(root, path) {
    let node = root;
    for (let i = 0; i < path.length; i++) {
      const step = path[i];
      if (step === "children") continue;
      if (typeof step === "number") {
        node = getNthSignificantChild(node, step);
        if (!node) return null;
      }
    }
    return node;
  }

  function resolveParent(root, path) {
    // For replace_children patches, resolve to the parent element at path
    if (path.length === 0) return root;
    // Walk path but stop before the last "children" marker
    let node = root;
    for (let i = 0; i < path.length; i++) {
      const step = path[i];
      if (step === "children") return node;
      if (typeof step === "number") {
        node = getNthSignificantChild(node, step);
        if (!node) return null;
      }
    }
    return node;
  }

  function getNthSignificantChild(node, n) {
    const children = node.childNodes;
    let realIdx = 0;
    for (let j = 0; j < children.length; j++) {
      const child = children[j];
      // Skip whitespace-only text nodes
      if (child.nodeType === 3 && child.textContent.trim() === "") continue;
      if (realIdx === n) return child;
      realIdx++;
    }
    return null;
  }

  // Connect!
  connect();
})();
