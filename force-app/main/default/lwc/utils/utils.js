import { ShowToastEvent } from 'lightning/platformShowToastEvent';

// ============================================================================
// CONSTANTS
// ============================================================================

// BIP32 derivation path constants for Cardano
export const BIP32_PURPOSE = 1852;  // Cardano purpose
export const BIP32_COIN_TYPE = 1815; // Cardano coin type
export const DERIVATION_PATHS = {
    RECEIVING: 0,
    CHANGE: 1,
    STAKE: 2
};

// Address type constants
export const ADDRESS_TYPES = {
    RECEIVING: '0',
    CHANGE: '1'
};

// Helper function for BIP32 hardening
export const HARDENING_OFFSET = 0x80000000;
export const harden = (num) => HARDENING_OFFSET + num;

// ============================================================================
// UTILITY FUNCTIONS
// ============================================================================

export function showToast(component, title, message, variant) {
    component.dispatchEvent(
        new ShowToastEvent({ title, message, variant })
    );
}

export function isAddressActuallyUsed(stats) {
    const { assetsInserted = 0, assetsUpdated = 0, transactionsInserted = 0, transactionsUpdated = 0 } = stats;
    return assetsInserted > 0 || assetsUpdated > 0 || transactionsInserted > 0 || transactionsUpdated > 0;
}

export function truncateText(text, maxLength, firstChars, lastChars) {
    if (!text || text.length <= maxLength) {
        return text;
    }
    const firstPart = text.substring(0, firstChars);
    const lastPart = text.substring(text.length - lastChars);
    return `${firstPart}...${lastPart}`;
} 