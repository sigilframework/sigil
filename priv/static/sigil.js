/**
 * Sigil.js — lightweight client runtime for Sigil.Live
 *
 * Opens a WebSocket to the server, joins the Live session,
 * captures DOM events, and applies server-sent patches.
 */
(function() {
  "use strict";

  var root = document.querySelector("[data-sigil-session]");
  if (!root) return;

  var sessionId = root.dataset.sigilSession;
  var csrfToken = root.dataset.sigilCsrf || "";
  var proto = location.protocol === "https:" ? "wss:" : "ws:";
  var wsUrl = proto + "//" + location.host + "/__sigil/websocket";
  var ws = null;
  var joined = false;
  var retries = 0;
  var MAX_RETRIES = 20;
  var BASE_DELAY = 500;

  function connect() {
    ws = new WebSocket(wsUrl);

    ws.onopen = function() {
      retries = 0;
      ws.send(JSON.stringify({
        type: "join",
        session: sessionId,
        csrf: csrfToken,
        view: root.dataset.sigilView || "",
        path: location.pathname
      }));
    };

    ws.onmessage = function(e) {
      var msg;
      try { msg = JSON.parse(e.data); } catch(_) { return; }

      if (msg.type === "joined") {
        joined = true;
      } else if (msg.type === "patch") {
        applyPatches(msg.patches);
      } else if (msg.type === "error") {
        console.warn("[Sigil] error:", msg.reason);
        if (msg.action === "reload") { retries = MAX_RETRIES; location.reload(); return; }
        if (msg.reason === "csrf_failed") retries = MAX_RETRIES;
      }
    };

    ws.onclose = function() {
      joined = false;
      if (retries < MAX_RETRIES) {
        retries++;
        setTimeout(connect, Math.min(BASE_DELAY * Math.pow(2, retries - 1), 30000));
      }
    };

    ws.onerror = function() { ws.close(); };
  }

  // --- Event delegation ---

  root.addEventListener("click", function(e) {
    // sigil-click="event_name"
    var el = e.target.closest("[sigil-click]");
    if (el) { e.preventDefault(); send(el.getAttribute("sigil-click"), getValues(el)); return; }

    // sigil-event="event_name" (alternative click binding)
    var evEl = e.target.closest("[sigil-event]");
    if (evEl && evEl.tagName !== "FORM") { e.preventDefault(); send(evEl.getAttribute("sigil-event"), getValues(evEl)); }
  });

  root.addEventListener("submit", function(e) {
    // sigil-submit="event_name"
    var form = e.target.closest("[sigil-submit]");
    if (!form) form = e.target.closest("[sigil-event]");
    if (form && form.tagName === "FORM") {
      e.preventDefault();
      var eventName = form.getAttribute("sigil-submit") || form.getAttribute("sigil-event");
      var data = Object.fromEntries(new FormData(form));
      send(eventName, data);
      // Only clear inputs on forms that opt in (e.g., chat input)
      if (form.hasAttribute("data-sigil-clear")) {
        form.querySelectorAll('input[type="text"], input:not([type]), textarea').forEach(function(el) {
          el.value = "";
        });
      }
    }
  });

  root.addEventListener("input", function(e) {
    var el = e.target.closest("[sigil-change]");
    if (el) send(el.getAttribute("sigil-change"), { value: el.value });
  });

  root.addEventListener("keydown", function(e) {
    var el = e.target.closest("[sigil-keydown]");
    if (el) send(el.getAttribute("sigil-keydown"), { key: e.key, value: el.value });
  });

  function send(event, value) {
    if (ws && ws.readyState === 1) {
      ws.send(JSON.stringify({ type: "event", event: event, value: value }));
    }
  }

  function getValues(el) {
    var v = {};
    // sigil-value-key="val" pattern
    Array.from(el.attributes).forEach(function(attr) {
      if (attr.name.startsWith("sigil-value-")) {
        v[attr.name.replace("sigil-value-", "")] = attr.value;
      }
    });
    // Legacy data-sigil-value (JSON)
    if (el.dataset.sigilValue) {
      try { Object.assign(v, JSON.parse(el.dataset.sigilValue)); } catch(_) {}
    }
    if (el.value !== undefined && el.tagName === "INPUT") v.value = el.value;
    return v;
  }

  // --- Patching ---

  function applyPatches(patches) {
    // Save scroll positions and focused input before patching
    var scrollEls = root.querySelectorAll("[data-sigil-scroll]");
    var scrollPositions = {};
    scrollEls.forEach(function(el) {
      var key = el.id || el.getAttribute("data-sigil-scroll");
      if (key) {
        scrollPositions[key] = {
          top: el.scrollTop,
          height: el.scrollHeight,
          atBottom: el.scrollTop + el.clientHeight >= el.scrollHeight - 50
        };
      }
    });

    // Save all form input values before patching (prevents data loss on re-render)
    var savedFields = {};
    root.querySelectorAll("input, textarea, select").forEach(function(el) {
      var key = el.name || el.id;
      if (key) {
        savedFields[key] = { value: el.value, type: el.type };
        if (el.type === "checkbox") savedFields[key].checked = el.checked;
      }
    });

    // Save focused input cursor position
    var activeEl = document.activeElement;
    var focusedName = null;
    if (activeEl && (activeEl.tagName === "INPUT" || activeEl.tagName === "TEXTAREA") && root.contains(activeEl)) {
      focusedName = activeEl.name || activeEl.id;
      if (focusedName && savedFields[focusedName]) {
        savedFields[focusedName].selStart = activeEl.selectionStart;
        savedFields[focusedName].selEnd = activeEl.selectionEnd;
        savedFields[focusedName].focused = true;
      }
    }

    var didReplaceHTML = false;

    for (var i = 0; i < patches.length; i++) {
      var p = patches[i];
      try {
        if (p.op === "replace_inner") {
          root.innerHTML = p.html;
          didReplaceHTML = true;
        } else if (p.op === "replace_children") {
          var parent = p.target_id ? document.getElementById(p.target_id) : resolveParent(root, p.path);
          if (parent) { parent.innerHTML = p.html; didReplaceHTML = true; }
        } else if (p.op === "text") {
          var node = resolve(root, p.path);
          if (node) node.textContent = p.content;
        } else if (p.op === "replace") {
          var node = resolve(root, p.path);
          if (node && node.nodeType === 1) node.outerHTML = p.html;
        } else if (p.op === "insert") {
          var parent = resolveParent(root, p.path);
          if (parent) { var t = document.createElement("div"); t.innerHTML = p.html; while (t.firstChild) parent.appendChild(t.firstChild); }
        } else if (p.op === "remove") {
          var node = resolve(root, p.path);
          if (node && node.parentNode) node.parentNode.removeChild(node);
        } else if (p.op === "attr") {
          var node = resolve(root, p.path);
          if (node && node.setAttribute) node.setAttribute(p.key, p.value);
        } else if (p.op === "remove_attr") {
          var node = resolve(root, p.path);
          if (node && node.removeAttribute) node.removeAttribute(p.key);
        }
      } catch(err) {
        console.warn("[Sigil] patch error:", p.op, err);
      }
    }

    // Restore scroll positions — auto-scroll to bottom if user was near bottom
    var newScrollEls = root.querySelectorAll("[data-sigil-scroll]");
    newScrollEls.forEach(function(el) {
      var key = el.id || el.getAttribute("data-sigil-scroll");
      if (key && scrollPositions[key]) {
        if (scrollPositions[key].atBottom) {
          el.scrollTop = el.scrollHeight;
        } else {
          el.scrollTop = scrollPositions[key].top;
        }
      } else {
        el.scrollTop = el.scrollHeight;
      }
    });

    // Restore all form field values
    Object.keys(savedFields).forEach(function(key) {
      var saved = savedFields[key];
      var el = root.querySelector('[name="' + key + '"]') || root.querySelector('#' + key);
      if (!el) return;
      if (el.type === "hidden" && el.getAttribute("data-sigil-server") !== null) return;
      el.value = saved.value;
      if (saved.type === "checkbox") el.checked = saved.checked;
      if (saved.focused) {
        el.focus();
        try { el.setSelectionRange(saved.selStart, saved.selEnd); } catch(_) {}
      }
    });

    // Re-execute scripts only after innerHTML replacement
    if (didReplaceHTML) {
      if (!window.__sigilLoadedScripts) window.__sigilLoadedScripts = {};
      var scripts = root.querySelectorAll("script");
      scripts.forEach(function(oldScript) {
        // Skip external scripts that are already loaded
        if (oldScript.src && window.__sigilLoadedScripts[oldScript.src]) return;

        var newScript = document.createElement("script");
        Array.from(oldScript.attributes).forEach(function(attr) {
          newScript.setAttribute(attr.name, attr.value);
        });
        if (!oldScript.src && oldScript.textContent) {
          newScript.textContent = oldScript.textContent;
        }
        if (oldScript.src) window.__sigilLoadedScripts[oldScript.src] = true;
        oldScript.parentNode.replaceChild(newScript, oldScript);
      });
    }
  }

  function resolve(root, path) {
    var node = root;
    for (var i = 0; i < path.length; i++) {
      if (path[i] === "children") continue;
      if (typeof path[i] === "number") {
        node = nthChild(node, path[i]);
        if (!node) return null;
      }
    }
    return node;
  }

  function resolveParent(root, path) {
    if (!path || path.length === 0) return root;
    var node = root;
    for (var i = 0; i < path.length; i++) {
      if (path[i] === "children") return node;
      if (typeof path[i] === "number") {
        node = nthChild(node, path[i]);
        if (!node) return null;
      }
    }
    return node;
  }

  function nthChild(node, n) {
    var kids = node.childNodes, idx = 0;
    for (var j = 0; j < kids.length; j++) {
      if (kids[j].nodeType === 3 && kids[j].textContent.trim() === "") continue;
      if (idx === n) return kids[j];
      idx++;
    }
    return null;
  }

  connect();
})();
