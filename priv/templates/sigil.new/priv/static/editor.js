/**
 * Sigil Rich Text Editor
 *
 * Wraps Quill.js (bubble theme) with markdown conversion.
 * - On load: markdown → HTML (via marked) → Quill
 * - On save: Quill → HTML → markdown (via Turndown) → hidden input
 * - Auto-save with debounce (1s after last input)
 * - Image uploads via /admin/uploads
 *
 * Guard: Uses window.__sigilQuill to prevent re-initialization
 * when sigil.js re-executes scripts after DOM patches.
 */
(function () {
  "use strict";

  var editorEl = document.getElementById("sigil-editor");
  if (!editorEl) return;

  // Guard: skip if Quill is already initialized on this element
  if (window.__sigilQuill) {
    // Re-attach event listeners for auto-save (they were lost in DOM replacement)
    attachFieldListeners();
    return;
  }

  var hiddenInput = document.getElementById("body-input");
  var initialMarkdown = editorEl.dataset.markdown || "";

  // --- Convert initial markdown to HTML ---
  var initialHTML = typeof marked !== "undefined"
    ? marked.parse(initialMarkdown)
    : initialMarkdown;

  // --- Initialize Quill ---
  var quill = new Quill("#sigil-editor", {
    theme: "bubble",
    placeholder: "Start writing your post...",
    modules: {
      toolbar: [
        ["bold", "italic", "underline", "strike"],
        ["link", "blockquote", "code-block"],
        [{ header: 2 }, { header: 3 }],
        [{ list: "ordered" }, { list: "bullet" }],
        ["image"],
        ["clean"]
      ]
    }
  });

  // Store globally to prevent re-initialization
  window.__sigilQuill = quill;

  // Set initial content
  if (initialHTML.trim()) {
    quill.root.innerHTML = initialHTML;
  }

  // --- Custom image handler ---
  quill.getModule("toolbar").addHandler("image", function () {
    var input = document.createElement("input");
    input.type = "file";
    input.accept = "image/*";
    input.onchange = function () {
      if (input.files && input.files[0]) {
        uploadImage(input.files[0]);
      }
    };
    input.click();
  });

  // --- Drag & drop images ---
  quill.root.addEventListener("drop", function (e) {
    e.preventDefault();
    var files = e.dataTransfer && e.dataTransfer.files;
    if (files) {
      for (var i = 0; i < files.length; i++) {
        if (files[i].type.startsWith("image/")) {
          uploadImage(files[i]);
        }
      }
    }
  });

  quill.root.addEventListener("dragover", function (e) {
    e.preventDefault();
  });

  // --- Paste images ---
  quill.root.addEventListener("paste", function (e) {
    var items = e.clipboardData && e.clipboardData.items;
    if (!items) return;
    for (var i = 0; i < items.length; i++) {
      if (items[i].type.startsWith("image/")) {
        e.preventDefault();
        var file = items[i].getAsFile();
        if (file) uploadImage(file);
        return;
      }
    }
  });

  function uploadImage(file) {
    var formData = new FormData();
    formData.append("file", file);

    var range = quill.getSelection(true);
    quill.insertText(range.index, "Uploading image...", { italic: true, color: "#999" });
    quill.setSelection(range.index + 18);

    fetch("/admin/uploads", {
      method: "POST",
      body: formData
    })
      .then(function (res) { return res.json(); })
      .then(function (data) {
        quill.deleteText(range.index, 18);
        if (data.url) {
          quill.insertEmbed(range.index, "image", data.url);
          quill.setSelection(range.index + 1);
        }
      })
      .catch(function (err) {
        quill.deleteText(range.index, 18);
        console.error("[Editor] Upload failed:", err);
      });
  }

  // --- Sync editor content to hidden input ---
  quill.on("text-change", function () {
    syncToInput();
    markDirty();
  });

  function syncToInput() {
    if (!hiddenInput) return;
    var html = quill.root.innerHTML;

    if (typeof TurndownService !== "undefined") {
      var td = new TurndownService({
        headingStyle: "atx",
        codeBlockStyle: "fenced",
        bulletListMarker: "-"
      });
      td.addRule("codeBlock", {
        filter: function (node) {
          return node.nodeName === "PRE" && node.querySelector("code");
        },
        replacement: function (content, node) {
          var code = node.querySelector("code");
          return "\n```\n" + code.textContent + "\n```\n";
        }
      });
      hiddenInput.value = td.turndown(html);
    } else {
      hiddenInput.value = html;
    }
  }

  // --- Dirty tracking & beforeunload ---
  var isDirty = false;

  function markDirty() {
    isDirty = true;
  }

  function markClean() {
    isDirty = false;
  }

  window.addEventListener("beforeunload", function (e) {
    if (isDirty) {
      e.preventDefault();
      e.returnValue = "";
    }
  });

  // --- Auto-save with debounce ---
  var autoSaveTimer = null;
  var DEBOUNCE_MS = 1000;

  function scheduleAutoSave() {
    markDirty();
    clearTimeout(autoSaveTimer);
    autoSaveTimer = setTimeout(triggerAutoSave, DEBOUNCE_MS);
  }

  function triggerAutoSave() {
    var trigger = document.getElementById("auto-save-trigger");
    if (!trigger) return;

    // Sync editor content first
    syncToInput();

    // Collect all field values into sigil-value-* attributes
    var titleEl = document.getElementById("title");
    var bodyEl = document.getElementById("body-input");
    var tagsEl = document.getElementById("tags");
    var publishedEl = document.getElementById("published-input");
    var publishedAtEl = document.getElementById("published_at");

    trigger.setAttribute("sigil-value-title", titleEl ? titleEl.value : "");
    trigger.setAttribute("sigil-value-body", bodyEl ? bodyEl.value : "");
    trigger.setAttribute("sigil-value-tags", tagsEl ? tagsEl.value : "");
    trigger.setAttribute("sigil-value-published", publishedEl ? publishedEl.value : "false");
    trigger.setAttribute("sigil-value-published_at", publishedAtEl ? publishedAtEl.value : "");

    // Click the hidden trigger to send via WebSocket
    trigger.click();

    // Show saving indicator (client-side only)
    showSaveStatus("Saving\u2026", "text-stone-400");
    setTimeout(function () {
      showSaveStatus("Saved \u2713", "text-emerald-500");
      markClean();
      setTimeout(function () {
        showSaveStatus("", "");
      }, 2500);
    }, 600);
  }

  function showSaveStatus(text, colorClass) {
    var el = document.getElementById("save-status");
    if (el) {
      el.textContent = text;
      el.className = "text-xs font-medium transition-opacity duration-300 " + colorClass;
      el.style.opacity = text ? "1" : "0";
    }
  }

  // --- Attach input listeners for auto-save ---
  function attachFieldListeners() {
    var titleInput = document.getElementById("title");
    if (titleInput) titleInput.addEventListener("input", scheduleAutoSave);

    var tagsInput = document.getElementById("tags");
    if (tagsInput) tagsInput.addEventListener("input", scheduleAutoSave);

    var dateInput = document.getElementById("published_at");
    if (dateInput) dateInput.addEventListener("change", scheduleAutoSave);
  }

  // Listen for changes on all editable fields
  quill.on("text-change", scheduleAutoSave);
  attachFieldListeners();

  // Focus the editor
  quill.focus();

  // --- Word count ---
  function updateWordCount() {
    var text = quill.getText().trim();
    var count = text ? text.split(/\s+/).length : 0;
    var el = document.getElementById("word-count");
    if (el) el.textContent = count + " words";
  }

  quill.on("text-change", updateWordCount);
  updateWordCount();
})();
