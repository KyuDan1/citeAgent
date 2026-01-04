// CiteAgent Background Script
// Handles communication between content scripts and the native app

console.log("🟡 [Background] Script loaded");

// Keep track of active Overleaf tabs
let overleafTabs = new Set();

// Listen for messages from content scripts
browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
    console.log("🟡 [Background] Received message:", message);
    console.log("🟡 [Background] Sender:", sender);

    if (message.action === "contentScriptReady") {
        // Track this tab as an Overleaf tab
        if (sender.tab && sender.tab.id) {
            overleafTabs.add(sender.tab.id);
            console.log("🟡 [Background] ✅ Registered Overleaf tab:", sender.tab.id);
            console.log("🟡 [Background] Active tabs:", Array.from(overleafTabs));
        }
        sendResponse({ success: true });
        return false;
    }

    // Handle messages that need to be forwarded to content script
    if (message.action === "getSelectedText" || message.action === "replaceSelectedText" ||
        message.action === "appendToBibFile" || message.action === "getEditorContent" ||
        message.action === "setEditorContent") {
        console.log("🟡 [Background] Forwarding to content script:", message.action);
        // Forward to active Overleaf tab
        forwardToContentScript(message, sendResponse);
        return true; // Keep channel open for async response
    }

    // Handle other messages that need to be forwarded to native app
    if (message.action === "processCitation" || message.action === "searchPaper") {
        console.log("🟡 [Background] Forwarding to native app:", message.action);
        // Forward to native app
        forwardToNativeApp(message, sendResponse);
        return true; // Keep channel open for async response
    }

    console.log("🟡 [Background] ⚠️ Unknown message action:", message.action);
    sendResponse({ success: false, error: "Unknown action" });
    return false;
});

// Forward message to content script
async function forwardToContentScript(message, sendResponse) {
    try {
        console.log("🟡 [Background] 📤 Sending to content script:", message);

        // Get active Overleaf tab
        const tabs = await browser.tabs.query({ active: true, currentWindow: true });
        const activeTab = tabs[0];

        // Check if we have the tab registered, or if it's an Overleaf URL
        if (!activeTab) {
            console.error("🟡 [Background] ❌ No active tab");
            sendResponse({ success: false, error: "No active tab" });
            return;
        }

        // If not in overleafTabs but URL matches, add it
        if (!overleafTabs.has(activeTab.id) && activeTab.url && activeTab.url.includes("overleaf.com")) {
            overleafTabs.add(activeTab.id);
            console.log("🟡 [Background] Auto-registered Overleaf tab:", activeTab.id);
        }

        if (!overleafTabs.has(activeTab.id)) {
            console.error("🟡 [Background] ❌ No active Overleaf tab");
            sendResponse({ success: false, error: "No active Overleaf tab" });
            return;
        }

        console.log("🟡 [Background] Sending to tab:", activeTab.id);
        const response = await browser.tabs.sendMessage(activeTab.id, message);
        console.log("🟡 [Background] 📥 Response from content script:", response);
        sendResponse(response);
    } catch (error) {
        console.error("🟡 [Background] ❌ Error communicating with content script:", error);
        console.error("🟡 [Background] Error details:", error.message, error.stack);
        sendResponse({ success: false, error: error.message });
    }
}

// Forward message to native app (SafariWebExtensionHandler)
async function forwardToNativeApp(message, sendResponse) {
    try {
        console.log("🟡 [Background] 📤 Sending to native app:", message);
        const response = await browser.runtime.sendNativeMessage(message);
        console.log("🟡 [Background] 📥 Response from native app:", response);
        sendResponse(response);
    } catch (error) {
        console.error("🟡 [Background] ❌ Error communicating with native app:", error);
        console.error("🟡 [Background] Error details:", error.message, error.stack);
        sendResponse({ success: false, error: error.message });
    }
}

// Get currently active Overleaf tab
async function getActiveOverleafTab() {
    const tabs = await browser.tabs.query({ active: true, currentWindow: true });
    const activeTab = tabs[0];

    if (activeTab && overleafTabs.has(activeTab.id)) {
        return activeTab;
    }

    // Check if current tab is an Overleaf page
    if (activeTab && activeTab.url && activeTab.url.includes("overleaf.com")) {
        overleafTabs.add(activeTab.id);
        return activeTab;
    }

    return null;
}

// Send message to active Overleaf tab
async function sendToOverleaf(action, data = {}) {
    const tab = await getActiveOverleafTab();
    if (!tab) {
        throw new Error("No active Overleaf tab found");
    }

    const message = { action, ...data };
    return browser.tabs.sendMessage(tab.id, message);
}

// Export functions for popup
window.sendToOverleaf = sendToOverleaf;
window.getActiveOverleafTab = getActiveOverleafTab;

// Clean up when tabs are closed
browser.tabs.onRemoved.addListener((tabId) => {
    if (overleafTabs.has(tabId)) {
        overleafTabs.delete(tabId);
        console.log("[CiteAgent Background] Removed tab:", tabId);
    }
});
