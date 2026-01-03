// CiteAgent Popup Script
console.log("[CiteAgent Popup] Loaded");

// UI Elements - Main View
const mainView = document.getElementById('mainView');
const addCitationsBtn = document.getElementById('addCitationsBtn');
const settingsBtn = document.getElementById('settingsBtn');
const statusDot = document.getElementById('statusDot');
const statusText = document.getElementById('statusText');
const errorDiv = document.getElementById('errorDiv');

// UI Elements - Settings View
const settingsView = document.getElementById('settingsView');
const backBtn = document.getElementById('backBtn');
const geminiApiKeyInput = document.getElementById('geminiApiKey');
const semanticScholarApiKeyInput = document.getElementById('semanticScholarApiKey');
const saveSettingsBtn = document.getElementById('saveSettingsBtn');

// State
let isProcessing = false;
let apiKeys = {
    gemini: '',
    semanticScholar: ''
};

// Update status
function setStatus(status, message) {
    statusText.textContent = message;
    statusDot.classList.remove('processing');

    if (status === 'processing') {
        statusDot.classList.add('processing');
    }
}

// Show error
function showError(message) {
    errorDiv.textContent = message;
    errorDiv.style.display = 'block';
    setTimeout(() => {
        errorDiv.style.display = 'none';
    }, 5000);
}

// Add Citations button click
addCitationsBtn.addEventListener('click', async () => {
    if (isProcessing) return;

    isProcessing = true;
    addCitationsBtn.disabled = true;
    setStatus('processing', 'Getting selected text...');

    try {
        // Check if API key is configured
        if (!apiKeys.gemini) {
            throw new Error('Please configure your Gemini API key in Settings first');
        }

        // Get active tab
        const tabs = await browser.tabs.query({ active: true, currentWindow: true });
        const activeTab = tabs[0];

        if (!activeTab.url || !activeTab.url.includes('overleaf.com')) {
            throw new Error('Please open an Overleaf project');
        }

        // Get selected text from content script
        setStatus('processing', 'Reading selection...');
        const response = await browser.tabs.sendMessage(activeTab.id, {
            action: 'getSelectedText'
        });

        if (!response.success || !response.text) {
            throw new Error('No text selected. Please select text in the Overleaf editor.');
        }

        console.log('[CiteAgent Popup] Selected text:', response.text.substring(0, 100) + '...');

        // Send to native app for processing
        setStatus('processing', 'Processing citations...');
        const result = await browser.runtime.sendNativeMessage({
            action: 'processCitation',
            text: response.text,
            geminiApiKey: apiKeys.gemini,
            semanticScholarApiKey: apiKeys.semanticScholar
        });

        if (!result.success) {
            throw new Error(result.error || 'Failed to process citations');
        }

        // Replace text in editor
        setStatus('processing', 'Updating editor...');
        await browser.tabs.sendMessage(activeTab.id, {
            action: 'replaceSelectedText',
            text: result.modifiedText
        });

        // Add BibTeX entries to .bib file
        if (result.bibtexEntries && result.bibtexEntries.length > 0) {
            setStatus('processing', 'Adding BibTeX entries...');
            await browser.tabs.sendMessage(activeTab.id, {
                action: 'appendToBibFile',
                entries: result.bibtexEntries,
                bibFilename: 'mybib.bib'
            });
        }

        setStatus('ready', 'Done! ✓');
        setTimeout(() => {
            setStatus('ready', 'Ready');
        }, 2000);

    } catch (error) {
        console.error('[CiteAgent Popup] Error:', error);
        setStatus('ready', 'Error');
        showError(error.message);
    } finally {
        isProcessing = false;
        addCitationsBtn.disabled = false;
    }
});

// Load settings from storage
async function loadSettings() {
    try {
        const result = await browser.storage.local.get(['geminiApiKey', 'semanticScholarApiKey']);
        apiKeys.gemini = result.geminiApiKey || '';
        apiKeys.semanticScholar = result.semanticScholarApiKey || '';

        geminiApiKeyInput.value = apiKeys.gemini;
        semanticScholarApiKeyInput.value = apiKeys.semanticScholar;

        console.log('[CiteAgent Popup] Settings loaded');
    } catch (error) {
        console.error('[CiteAgent Popup] Error loading settings:', error);
    }
}

// Save settings to storage
async function saveSettings() {
    try {
        apiKeys.gemini = geminiApiKeyInput.value.trim();
        apiKeys.semanticScholar = semanticScholarApiKeyInput.value.trim();

        await browser.storage.local.set({
            geminiApiKey: apiKeys.gemini,
            semanticScholarApiKey: apiKeys.semanticScholar
        });

        console.log('[CiteAgent Popup] Settings saved');
        showSettings(false);
        setStatus('ready', 'Settings saved ✓');
        setTimeout(() => setStatus('ready', 'Ready'), 2000);
    } catch (error) {
        console.error('[CiteAgent Popup] Error saving settings:', error);
        showError('Failed to save settings');
    }
}

// Show/hide settings view
function showSettings(show) {
    if (show) {
        mainView.style.display = 'none';
        settingsView.style.display = 'block';
    } else {
        mainView.style.display = 'block';
        settingsView.style.display = 'none';
    }
}

// Settings button click
settingsBtn.addEventListener('click', () => {
    showSettings(true);
});

// Back button click
backBtn.addEventListener('click', () => {
    showSettings(false);
});

// Save settings button click
saveSettingsBtn.addEventListener('click', () => {
    saveSettings();
});

// Initialize on load
loadSettings();
setStatus('ready', 'Ready');
