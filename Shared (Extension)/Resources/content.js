// CiteAgent Content Script - Overleaf Editor Control
// This script runs on Overleaf pages and provides functions to read/write editor content

console.log("[CiteAgent] Content script loaded on Overleaf");

// Add visible indicator that content script is loaded
function showLoadedIndicator() {
    const indicator = document.createElement('div');
    indicator.id = 'citeagent-loaded-indicator';
    indicator.textContent = '✅ CiteAgent Loaded';
    indicator.style.cssText = `
        position: fixed;
        top: 10px;
        right: 10px;
        background: #4CAF50;
        color: white;
        padding: 8px 16px;
        border-radius: 4px;
        font-family: sans-serif;
        font-size: 14px;
        z-index: 999999;
        box-shadow: 0 2px 8px rgba(0,0,0,0.2);
    `;
    document.body.appendChild(indicator);

    // Remove after 3 seconds
    setTimeout(() => {
        indicator.style.transition = 'opacity 0.5s';
        indicator.style.opacity = '0';
        setTimeout(() => indicator.remove(), 500);
    }, 3000);
}

// Show indicator when page is ready
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', showLoadedIndicator);
} else {
    showLoadedIndicator();
}

// Diagnostic function to explore the page
function diagnoseOverleafPage() {
    console.log("=== OVERLEAF PAGE DIAGNOSTIC ===");
    console.log("URL:", window.location.href);

    // Check for common editor elements
    const selectors = [
        '.cm-editor',
        '.cm-content',
        '.source-editor',
        '.cm-scroller',
        '.editor-panel',
        '.ace_editor',
        '#editor',
        '[class*="editor"]',
        '[class*="codemirror"]',
        '[class*="cm-"]'
    ];

    selectors.forEach(selector => {
        const elements = document.querySelectorAll(selector);
        if (elements.length > 0) {
            console.log(`Found ${elements.length} elements matching "${selector}"`);
            elements.forEach((el, i) => {
                console.log(`  [${i}]:`, el.className, el);
            });
        }
    });

    // Check window objects
    console.log("window.editor:", window.editor);
    console.log("window.aceEditor:", window.aceEditor);
    console.log("window.cm:", window.cm);

    console.log("=== END DIAGNOSTIC ===");
}

// Run diagnostic after a short delay to let page load
setTimeout(diagnoseOverleafPage, 2000);

// Helper function to get the Overleaf editor instance
function getOverleafEditor() {
    console.log("[CiteAgent] Attempting to find Overleaf editor...");

    // Method 1: Try to find CodeMirror 6 editor through DOM
    const cmEditors = document.querySelectorAll('.cm-editor');
    console.log("[CiteAgent] Found .cm-editor elements:", cmEditors.length);

    if (cmEditors.length > 0) {
        for (let elem of cmEditors) {
            // Log all properties to debug
            console.log("[CiteAgent] Inspecting element properties:", Object.keys(elem));

            // Try different paths to access the editor view
            let view = elem.cmView?.view || elem.cmView || elem.CodeMirror?.view || elem.CodeMirror;

            // Sometimes the view is directly on the element
            if (!view && elem.view) {
                view = elem.view;
            }

            // Try accessing through data attributes or custom properties
            for (let key in elem) {
                if (key.includes('cm') || key.includes('CM') || key.includes('editor')) {
                    const prop = elem[key];
                    if (prop && typeof prop === 'object' && prop.state && prop.state.doc) {
                        console.log("[CiteAgent] Found editor via property:", key);
                        return { type: 'codemirror6', editor: prop };
                    }
                }
            }

            // Check if we have a valid CodeMirror 6 view
            if (view && view.state && view.state.doc) {
                console.log("[CiteAgent] Found CodeMirror 6 editor via DOM");
                return { type: 'codemirror6', editor: view };
            }

            // If we found a .cm-editor but can't access the view, return it anyway
            // We'll use a fallback method for selection
            if (elem.classList.contains('cm-editor')) {
                console.log("[CiteAgent] Found .cm-editor element, will use fallback selection method");
                return { type: 'codemirror6-fallback', element: elem };
            }
        }
    }

    // Method 2: Try window.editor
    if (window.editor) {
        console.log("[CiteAgent] Found window.editor");
        let view = window.editor.view || window.editor;
        if (view && view.state && view.state.doc) {
            return { type: 'codemirror6', editor: view };
        }
    }

    // Method 3: Try to find through Angular scope (Overleaf uses Angular)
    const editorContainer = document.querySelector('[ng-controller*="Editor"]') ||
                           document.querySelector('.editor-panel');
    if (editorContainer && editorContainer.cmView) {
        console.log("[CiteAgent] Found editor via Angular scope");
        return { type: 'codemirror6', editor: editorContainer.cmView };
    }

    // Method 4: Fallback to ACE editor (old Overleaf)
    let aceEditor = window.aceEditor || (typeof ace !== 'undefined' && ace.edit && ace.edit('editor'));
    if (aceEditor && aceEditor.getValue) {
        console.log("[CiteAgent] Found ACE editor");
        return { type: 'ace', editor: aceEditor };
    }

    console.log("[CiteAgent] No editor found");
    return null;
}

// Get all editor content
function getEditorContent() {
    const editorObj = getOverleafEditor();
    if (!editorObj) return null;

    if (editorObj.type === 'codemirror6') {
        return editorObj.editor.state.doc.toString();
    } else if (editorObj.type === 'ace') {
        return editorObj.editor.getValue();
    }

    return null;
}

// Set all editor content
function setEditorContent(content) {
    const editorObj = getOverleafEditor();
    if (!editorObj) return false;

    try {
        if (editorObj.type === 'codemirror6') {
            const view = editorObj.editor;
            const transaction = view.state.update({
                changes: { from: 0, to: view.state.doc.length, insert: content }
            });
            view.dispatch(transaction);
            return true;
        } else if (editorObj.type === 'ace') {
            editorObj.editor.setValue(content, -1);
            return true;
        }
    } catch (e) {
        console.error("[CiteAgent] Error setting content:", e);
        return false;
    }

    return false;
}

// Get selected text
function getSelectedText() {
    const editorObj = getOverleafEditor();
    console.log("[CiteAgent] Editor object:", editorObj);

    if (!editorObj) {
        console.log("[CiteAgent] No editor found");
        return null;
    }

    if (editorObj.type === 'codemirror6') {
        const view = editorObj.editor;
        const selection = view.state.selection.main;
        console.log("[CiteAgent] CM6 selection:", { from: selection.from, to: selection.to });
        if (selection.from !== selection.to) {
            const text = view.state.doc.sliceString(selection.from, selection.to);
            console.log("[CiteAgent] Selected text length:", text.length);
            return text;
        }
        console.log("[CiteAgent] No text selected (from === to)");
        return null;
    } else if (editorObj.type === 'codemirror6-fallback') {
        // Use browser's native selection API as fallback
        console.log("[CiteAgent] Using fallback selection method");
        const selection = window.getSelection();
        if (selection && selection.toString().trim()) {
            const text = selection.toString();
            console.log("[CiteAgent] Fallback selected text length:", text.length);
            return text;
        }
        console.log("[CiteAgent] No text selected via fallback");
        return null;
    } else if (editorObj.type === 'ace') {
        const selected = editorObj.editor.getSelectedText();
        console.log("[CiteAgent] ACE selected text:", selected);
        return selected || null;
    }

    return null;
}

// Replace selected text
function replaceSelectedText(newText) {
    const editorObj = getOverleafEditor();
    if (!editorObj) return false;

    try {
        if (editorObj.type === 'codemirror6') {
            const view = editorObj.editor;
            const selection = view.state.selection.main;
            if (selection.from !== selection.to) {
                const transaction = view.state.update({
                    changes: { from: selection.from, to: selection.to, insert: newText }
                });
                view.dispatch(transaction);
                return true;
            }
            return false;
        } else if (editorObj.type === 'codemirror6-fallback') {
            // Use execCommand as fallback
            console.log("[CiteAgent] Using fallback replace method");
            const selection = window.getSelection();
            if (selection && selection.rangeCount > 0) {
                const range = selection.getRangeAt(0);
                range.deleteContents();
                range.insertNode(document.createTextNode(newText));
                return true;
            }
            return false;
        } else if (editorObj.type === 'ace') {
            editorObj.editor.session.replace(editorObj.editor.selection.getRange(), newText);
            return true;
        }
    } catch (e) {
        console.error("[CiteAgent] Error replacing selection:", e);
        return false;
    }

    return false;
}

// Get list of files in the project
function getFileList() {
    const fileItems = document.querySelectorAll('.file-tree-item-name, .entity-name');
    return Array.from(fileItems).map(item => item.textContent.trim()).filter(name => name);
}

// Switch to a different file
function switchToFile(filename) {
    // Try entity-name (newer UI)
    let entities = document.querySelectorAll('.entity-name');
    for (let entity of entities) {
        let text = entity.textContent.trim();
        if (text === filename || text.endsWith(filename)) {
            entity.click();
            return true;
        }
    }

    // Try file-tree-item-name (older UI)
    let fileItems = document.querySelectorAll('.file-tree-item-name');
    for (let item of fileItems) {
        let text = item.textContent.trim();
        if (text === filename || text.endsWith(filename)) {
            item.click();
            return true;
        }
    }

    return false;
}

// Wait for editor to be ready after file switch
function waitForEditor(timeout = 5000) {
    return new Promise((resolve) => {
        const startTime = Date.now();
        const checkInterval = setInterval(() => {
            if (getOverleafEditor() !== null) {
                clearInterval(checkInterval);
                resolve(true);
            } else if (Date.now() - startTime > timeout) {
                clearInterval(checkInterval);
                resolve(false);
            }
        }, 100);
    });
}

// Message listener from background script or native app
browser.runtime.onMessage.addListener((request, sender, sendResponse) => {
    console.log("🟢 [Content] Received message:", request);
    console.log("🟢 [Content] Sender:", sender);

    const action = request.action;

    try {
        if (action === "getEditorContent") {
            console.log("🟢 [Content] Getting editor content...");
            const content = getEditorContent();
            sendResponse({ success: content !== null, content: content });
            return true;

        } else if (action === "setEditorContent") {
            console.log("🟢 [Content] Setting editor content...");
            const success = setEditorContent(request.content);
            sendResponse({ success: success });
            return true;

        } else if (action === "getSelectedText") {
            console.log("🟢 [Content] Getting selected text...");
            const text = getSelectedText();
            console.log("🟢 [Content] Selected text:", text ? `${text.length} chars` : 'null');
            sendResponse({ success: text !== null, text: text });
            return true;

        } else if (action === "replaceSelectedText") {
            const success = replaceSelectedText(request.text);
            sendResponse({ success: success });
            return true;

        } else if (action === "getFileList") {
            const files = getFileList();
            sendResponse({ success: true, files: files });
            return true;

    } else if (action === "switchToFile") {
        switchToFile(request.filename);
        // Wait for editor to load, then respond
        waitForEditor().then(ready => {
            sendResponse({ success: ready });
        });
        return true; // Keep channel open for async response

    } else if (action === "appendToBibFile") {
        // Switch to bib file, wait for editor, then append content
        const bibFilename = request.bibFilename || "mybib.bib";
        switchToFile(bibFilename);

        waitForEditor(3000).then(ready => {
            if (!ready) {
                // Try alternative names
                const alternatives = ["references.bib", "bibliography.bib", "refs.bib"];
                let found = false;
                for (let alt of alternatives) {
                    if (alt !== bibFilename && switchToFile(alt)) {
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    sendResponse({ success: false, error: "Could not find .bib file" });
                    return;
                }
                // Wait again after switching to alternative
                return waitForEditor(3000);
            }
            return Promise.resolve(true);
        }).then(ready => {
            if (!ready) {
                sendResponse({ success: false, error: "Editor not ready" });
                return;
            }

            const currentContent = getEditorContent();
            if (currentContent === null) {
                sendResponse({ success: false, error: "Could not read .bib file" });
                return;
            }

            const newContent = currentContent.trimEnd() + "\n\n" + request.entries.join("\n\n") + "\n";
            const success = setEditorContent(newContent);

            // Switch back to main.tex
            setTimeout(() => {
                switchToFile("main.tex");
            }, 500);

            sendResponse({ success: success });
        });

        return true; // Keep channel open for async response
        }
    } catch (error) {
        console.error("🟢 [Content] ❌ Error in message handler:", error);
        sendResponse({ success: false, error: error.message });
        return true;
    }

    console.log("🟢 [Content] ⚠️ No handler for action:", action);
    return false;
});

// Notify background that content script is ready
console.log("🟢 [Content] Sending contentScriptReady message...");
browser.runtime.sendMessage({ action: "contentScriptReady", url: window.location.href })
    .then(() => console.log("🟢 [Content] ✅ Sent contentScriptReady"))
    .catch(err => console.error("🟢 [Content] ❌ Failed to send contentScriptReady:", err));
