// CiteAgent Background Script
// Handles communication between content scripts and the native app

console.log("[CiteAgent Background] Script loaded");

// Keep track of active Overleaf tabs
let overleafTabs = new Set();

// Listen for messages from content scripts
browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
    console.log("[CiteAgent Background] Received message:", message);

    if (message.action === "contentScriptReady") {
        // Track this tab as an Overleaf tab
        if (sender.tab && sender.tab.id) {
            overleafTabs.add(sender.tab.id);
            console.log("[CiteAgent Background] Registered Overleaf tab:", sender.tab.id);
        }
        return false;
    }

    // Handle other messages that need to be forwarded to native app
    if (message.action === "processCitation" || message.action === "searchPaper") {
        // Forward to native app
        forwardToNativeApp(message, sendResponse);
        return true; // Keep channel open for async response
    }

    return false;
});

// Forward message to native app (SafariWebExtensionHandler)
async function forwardToNativeApp(message, sendResponse) {
    try {
        console.log("[CiteAgent Background] Forwarding to native app:", message);
        const response = await browser.runtime.sendNativeMessage(message);
        console.log("[CiteAgent Background] Response from native app:", response);
        sendResponse(response);
    } catch (error) {
        console.error("[CiteAgent Background] Error communicating with native app:", error);
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
