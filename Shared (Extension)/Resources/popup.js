// CiteAgent Popup Script
console.log("[CiteAgent Popup] Loaded");

// UI Elements - Main View
const mainView = document.getElementById('mainView');
const addCitationsBtn = document.getElementById('addCitationsBtn');
const settingsBtn = document.getElementById('settingsBtn');
const statusDot = document.getElementById('statusDot');
const statusText = document.getElementById('statusText');
const errorDiv = document.getElementById('errorDiv');

// UI Elements - Quick Settings
const citationStyleSelect = document.getElementById('citationStyleSelect');
const citationDensitySlider = document.getElementById('citationDensitySlider');
const densityLabel = document.getElementById('densityLabel');
const minYearInput = document.getElementById('minYearInput');

// UI Elements - Settings View
const settingsView = document.getElementById('settingsView');
const backBtn = document.getElementById('backBtn');
const geminiApiKeyInput = document.getElementById('geminiApiKey');
const semanticScholarApiKeyInput = document.getElementById('semanticScholarApiKey');
const searchStrictnessSlider = document.getElementById('searchStrictnessSlider');
const strictnessLabel = document.getElementById('strictnessLabel');
const saveSettingsBtn = document.getElementById('saveSettingsBtn');

// State
let isProcessing = false;
let settings = {
    geminiApiKey: '',
    semanticScholarApiKey: '',
    citationStyle: 'cite',
    citationDensity: 50,
    searchStrictness: 30,
    minYear: 2020
};

// For backward compatibility
let apiKeys = {
    gemini: '',
    semanticScholar: ''
};

// Density label helper
function getDensityLabel(value) {
    if (value < 20) return 'Minimal';
    if (value < 40) return 'Light';
    if (value < 60) return 'Balanced';
    if (value < 80) return 'Thorough';
    return 'Comprehensive';
}

// Strictness label helper
function getStrictnessLabel(value) {
    if (value < 20) return 'Very Relaxed';
    if (value < 40) return 'Relaxed';
    if (value < 60) return 'Balanced';
    if (value < 80) return 'Strict';
    return 'Very Strict';
}

// Update density label on slider change
citationDensitySlider.addEventListener('input', (e) => {
    const value = parseInt(e.target.value);
    densityLabel.textContent = getDensityLabel(value);
    settings.citationDensity = value;
    // Auto-save quick settings
    saveQuickSettings();
});

// Update citation style on change
citationStyleSelect.addEventListener('change', (e) => {
    settings.citationStyle = e.target.value;
    // Auto-save quick settings
    saveQuickSettings();
});

// Update strictness label on slider change
searchStrictnessSlider.addEventListener('input', (e) => {
    const value = parseInt(e.target.value);
    strictnessLabel.textContent = getStrictnessLabel(value);
    settings.searchStrictness = value;
});

// Update min year on change
minYearInput.addEventListener('change', (e) => {
    const value = parseInt(e.target.value) || 2020;
    settings.minYear = value;
    saveQuickSettings();
});

// Save quick settings (auto-save)
async function saveQuickSettings() {
    try {
        await browser.storage.local.set({
            citationStyle: settings.citationStyle,
            citationDensity: settings.citationDensity,
            minYear: settings.minYear
        });
        console.log('[CiteAgent Popup] Quick settings auto-saved');
    } catch (error) {
        console.error('[CiteAgent Popup] Error saving quick settings:', error);
    }
}

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
    console.log('🔴 [Popup] Add Citations button clicked');

    if (isProcessing) {
        console.log('🔴 [Popup] Already processing, ignoring click');
        return;
    }

    isProcessing = true;
    addCitationsBtn.disabled = true;
    setStatus('processing', 'Getting selected text...');

    try {
        // Check if API key is configured
        console.log('🔴 [Popup] Checking API key...');
        if (!settings.geminiApiKey) {
            throw new Error('Please configure your Gemini API key in Settings first');
        }
        console.log('🔴 [Popup] API key present:', settings.geminiApiKey.substring(0, 10) + '...');

        // Get active tab
        console.log('🔴 [Popup] Getting active tab...');
        const tabs = await browser.tabs.query({ active: true, currentWindow: true });
        const activeTab = tabs[0];
        console.log('🔴 [Popup] Active tab:', activeTab.id, activeTab.url);

        if (!activeTab.url || !activeTab.url.includes('overleaf.com')) {
            throw new Error('Please open an Overleaf project');
        }

        // Get selected text from content script directly
        setStatus('processing', 'Reading selection...');
        console.log('🔴 [Popup] Sending getSelectedText message directly to tab:', activeTab.id);

        const response = await browser.tabs.sendMessage(activeTab.id, {
            action: 'getSelectedText'
        });

        console.log('🔴 [Popup] Received response:', response);

        if (!response) {
            throw new Error('Failed to communicate with Overleaf page. Please refresh the page and try again.');
        }

        if (!response.success || !response.text) {
            throw new Error('No text selected. Please select text in the Overleaf editor.');
        }

        console.log('🔴 [Popup] Selected text length:', response.text.length);
        console.log('🔴 [Popup] Selected text preview:', response.text.substring(0, 100) + '...');

        // Send to native app for processing directly
        setStatus('processing', 'Processing citations...');
        console.log('🔴 [Popup] Sending processCitation to native app...');
        console.log('🔴 [Popup] Settings:', {
            citationStyle: settings.citationStyle,
            citationDensity: settings.citationDensity,
            searchStrictness: settings.searchStrictness,
            minYear: settings.minYear
        });

        const result = await browser.runtime.sendNativeMessage({
            action: 'processCitation',
            text: response.text,
            geminiApiKey: settings.geminiApiKey,
            semanticScholarApiKey: settings.semanticScholarApiKey,
            citationStyle: settings.citationStyle,
            citationDensity: settings.citationDensity,
            searchStrictness: settings.searchStrictness,
            minYear: settings.minYear
        });

        console.log('🔴 [Popup] Received result from native app:', result);

        if (!result.success) {
            throw new Error(result.error || 'Failed to process citations');
        }

        // Replace text in editor directly
        setStatus('processing', 'Updating editor...');
        console.log('🔴 [Popup] Sending replaceSelectedText directly to tab');
        await browser.tabs.sendMessage(activeTab.id, {
            action: 'replaceSelectedText',
            text: result.modifiedText
        });

        // Add BibTeX entries to .bib file directly
        if (result.bibtexEntries && result.bibtexEntries.length > 0) {
            setStatus('processing', 'Adding BibTeX entries...');
            console.log('🔴 [Popup] Sending appendToBibFile directly to tab');
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
        const result = await browser.storage.local.get([
            'geminiApiKey',
            'semanticScholarApiKey',
            'citationStyle',
            'citationDensity',
            'searchStrictness',
            'minYear'
        ]);

        // Load all settings
        settings.geminiApiKey = result.geminiApiKey || '';
        settings.semanticScholarApiKey = result.semanticScholarApiKey || '';
        settings.citationStyle = result.citationStyle || 'cite';
        settings.citationDensity = result.citationDensity !== undefined ? result.citationDensity : 50;
        settings.searchStrictness = result.searchStrictness !== undefined ? result.searchStrictness : 30;
        settings.minYear = result.minYear !== undefined ? result.minYear : 2020;

        // For backward compatibility
        apiKeys.gemini = settings.geminiApiKey;
        apiKeys.semanticScholar = settings.semanticScholarApiKey;

        // Update UI - Settings View
        geminiApiKeyInput.value = settings.geminiApiKey;
        semanticScholarApiKeyInput.value = settings.semanticScholarApiKey;
        searchStrictnessSlider.value = settings.searchStrictness;
        strictnessLabel.textContent = getStrictnessLabel(settings.searchStrictness);

        // Update UI - Quick Settings
        citationStyleSelect.value = settings.citationStyle;
        citationDensitySlider.value = settings.citationDensity;
        densityLabel.textContent = getDensityLabel(settings.citationDensity);
        minYearInput.value = settings.minYear;

        console.log('[CiteAgent Popup] Settings loaded:', settings);
    } catch (error) {
        console.error('[CiteAgent Popup] Error loading settings:', error);
    }
}

// Save settings to storage
async function saveSettings() {
    try {
        settings.geminiApiKey = geminiApiKeyInput.value.trim();
        settings.semanticScholarApiKey = semanticScholarApiKeyInput.value.trim();
        settings.searchStrictness = parseInt(searchStrictnessSlider.value);

        // For backward compatibility
        apiKeys.gemini = settings.geminiApiKey;
        apiKeys.semanticScholar = settings.semanticScholarApiKey;

        await browser.storage.local.set({
            geminiApiKey: settings.geminiApiKey,
            semanticScholarApiKey: settings.semanticScholarApiKey,
            citationStyle: settings.citationStyle,
            citationDensity: settings.citationDensity,
            searchStrictness: settings.searchStrictness
        });

        console.log('[CiteAgent Popup] Settings saved:', settings);
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
