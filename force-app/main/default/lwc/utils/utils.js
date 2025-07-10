import { ShowToastEvent } from 'lightning/platformShowToastEvent';

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

export function showToast(component, title, message, variant) {
    component.dispatchEvent(
        new ShowToastEvent({ title, message, variant })
    );
} 