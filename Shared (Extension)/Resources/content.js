// CiteAgent Content Script - Overleaf Editor Control
// This script runs on Overleaf pages and provides functions to read/write editor content

console.log("[CiteAgent] Content script loaded on Overleaf");

// Helper function to get the Overleaf editor instance
function getOverleafEditor() {
    // Try CodeMirror 6 (new Overleaf)
    let elem = window.editor || document.querySelector('.cm-editor');
    if (elem) {
        let cmView = elem.CodeMirror || elem.cmView || elem.cm;
        if (cmView && cmView.view && cmView.view.state && cmView.view.state.doc) {
            return { type: 'codemirror6', editor: cmView.view };
        }
    }

    // Fallback to ACE editor (old Overleaf)
    let aceEditor = window.aceEditor || (typeof ace !== 'undefined' && ace.edit('editor'));
    if (aceEditor && aceEditor.getValue) {
        return { type: 'ace', editor: aceEditor };
    }

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
    if (!editorObj) return null;

    if (editorObj.type === 'codemirror6') {
        const view = editorObj.editor;
        const selection = view.state.selection.main;
        if (selection.from !== selection.to) {
            return view.state.doc.sliceString(selection.from, selection.to);
        }
        return null;
    } else if (editorObj.type === 'ace') {
        const selected = editorObj.editor.getSelectedText();
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
    console.log("[CiteAgent] Received message:", request);

    const action = request.action;

    if (action === "getEditorContent") {
        const content = getEditorContent();
        sendResponse({ success: content !== null, content: content });
        return true;

    } else if (action === "setEditorContent") {
        const success = setEditorContent(request.content);
        sendResponse({ success: success });
        return true;

    } else if (action === "getSelectedText") {
        const text = getSelectedText();
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

    return false;
});

// Notify background that content script is ready
browser.runtime.sendMessage({ action: "contentScriptReady", url: window.location.href });
