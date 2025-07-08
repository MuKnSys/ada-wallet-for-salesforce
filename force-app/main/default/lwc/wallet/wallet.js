import { LightningElement, track, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { loadScript } from 'lightning/platformResourceLoader';
import qrcodeLibrary from '@salesforce/resourceUrl/qrcode';
import getWalletAssetSummary from '@salesforce/apex/UTXOAssetController.getWalletAssetSummary';
import getFirstUnusedReceivingAddress from '@salesforce/apex/UTXOController.getFirstUnusedReceivingAddress';
import createOutboundTransaction from '@salesforce/apex/UTXOController.createOutboundTransaction';
import { subscribe, unsubscribe } from 'lightning/empApi';


export default class Wallet extends LightningElement {
    CHANNEL_NAME = '/event/WalletSyncEvent__e';
    
    _recordId;
    eventSubscription = null;
    
    @track balance = '0';
    @track paymentAddress = 'Loading payment address...';
    @track showReceive = false;
    @track showSend = false;
    @track isLoading = false;
    @track isAddressInvalid = false;
    @track isQrCodeLibraryLoaded = false;
    @track qrCodeError = false;
    @track assets = [];
    @track hasAssets = false;
    @track transactions = [];
    @track sendAmount = '';
    @track sendRecipient = '';
    @track errorMessage = '';
    @track isSendButtonDisabled = true;

    @api
    get recordId() {
        return this._recordId;
    }

    set recordId(value) {
        const recordIdChanged = this._recordId != value;
        this._recordId = value;

        if (this._recordId && recordIdChanged) {
            this.isLoading = true;
            this.fetchUtxoCounts();
        }
    }

    async renderedCallback() {
        if (!this.isQrCodeLibraryLoaded) {            
            await this.loadQrCodeLibrary();
        }

        if (this.showReceive && this.isQrCodeLibraryLoaded && this.paymentAddress && !this.isAddressInvalid && !this.qrCodeError) {
            this.generateQrCode();
        }
    }

    async loadQrCodeLibrary() {
        try {
            await loadScript(this, qrcodeLibrary);
            this.isQrCodeLibraryLoaded = true;
        } catch (error) {
            this.showToast('Error', 'Failed to load QR Code library.', 'error');
        }
    }    

    // Lightweight initialization
    async initializeWallet() {
        this.balance = '0';
        this.paymentAddress = 'Loading payment address...';
        this.isLoading = false;
    }

    async fetchUtxoCounts() {
        try {
            await this.updateWalletBalance();
            await this.updatePaymentAddress();
        } catch (error) {
            const message = error.body?.message || error.message || 'Unknown error';
            this.showToast('Error', message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async updateWalletBalance() {
        const summary = await getWalletAssetSummary({ walletId: this.recordId });
        
        if (summary.success) {
            this.balance = this.formatNumber(summary.adaBalance || 0, 6);
            this.assets = this.buildAssetRows(summary.tokens || []);
            this.hasAssets = this.assets.length > 0;
        } else {
            this.resetWalletData();
        }
    }

    buildAssetRows(tokens) {
        return tokens.map(token => ({
            id: token.unit || token.symbol,
            name: token.name || token.symbol,
            symbol: token.symbol || token.unit,
            amount: this.formatNumber(token.amount, token.decimals || 0),
            rawAmount: token.rawAmount,
            decimals: token.decimals,
            policyId: token.policyId,
            fingerprint: token.fingerprint,
            imgUrl: token.icon || null,
            icon: 'utility:apps'
        }));
    }

    resetWalletData() {
        this.balance = '0';
        this.assets = [];
        this.hasAssets = false;
        this.transactions = [];
    }

    async updatePaymentAddress() {
        const payAddr = await getFirstUnusedReceivingAddress({ walletId: this.recordId });
        this.paymentAddress = payAddr || 'No unused address available';
        this.isAddressInvalid = !payAddr;
    }

    generateQrCode() {
        if (!this.isQrCodeLibraryLoaded || !this.paymentAddress || this.isAddressInvalid) {
            this.qrCodeError = true;
            this.showToast('Error', 'Cannot generate QR code: Invalid address or library not loaded.', 'error');
            return;
        }

        try {
            const qrCodeElement = this.template.querySelector('.qr-code-canvas');
            if (qrCodeElement) {
                // Clear previous QR code by removing all child elements
                while (qrCodeElement.firstChild) {
                    qrCodeElement.removeChild(qrCodeElement.firstChild);
                }
                
                // Generate new QR code
                new QRCode(qrCodeElement, {
                    text: this.paymentAddress,
                    width: 200,
                    height: 200,
                    colorDark: '#000000',
                    colorLight: '#FFFFFF',
                    correctLevel: QRCode.CorrectLevel.H
                });
                this.qrCodeError = false;
            }
        } catch (error) {
            this.qrCodeError = true;
            this.showToast('Error', 'Failed to generate QR code.', 'error');
        }
    }

    openReceiveModal() {
        if (this.isAddressInvalid) {
            this.showToast('Error', 'Cannot open Receive modal: No valid payment address available.', 'error');
        } else {
            this.showReceive = true;
        }
    }

    closeReceiveModal() {
        this.showReceive = false;
    }

    openSendModal() {
        this.sendAmount = '';
        this.sendRecipient = '';
        this.errorMessage = '';
        this.isSendButtonDisabled = true;
        
        this.showSend = true;
    }

    closeSendModal() {
        this.showSend = false;
    }

    copyToClipboard() {
        if (navigator.clipboard && this.paymentAddress) {
            navigator.clipboard.writeText(this.paymentAddress).then(() => {
                this.showToast('Success', 'Address copied to clipboard!', 'success');
            }).catch(() => {
                this.showToast('Error', 'Failed to copy address to clipboard.', 'error');
            });
        } else {
            // Fallback for older browsers
            const textArea = document.createElement('textarea');
            textArea.value = this.paymentAddress;
            document.body.appendChild(textArea);
            textArea.select();
            try {
                document.execCommand('copy');
                this.showToast('Success', 'Address copied to clipboard!', 'success');
            } catch (err) {
                this.showToast('Error', 'Failed to copy address to clipboard.', 'error');
            }
            document.body.removeChild(textArea);
        }
    }

    shareLink() {
        this.showToast('Info', 'QR Code download functionality not implemented yet.', 'info');
    }

    showToast(title, message, variant) {
        const evt = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant,
        });
        this.dispatchEvent(evt);
    }

    connectedCallback() {
        this.subscribeToWalletSyncEvent();
    }

    disconnectedCallback() {
        this.unsubscribeFromWalletSyncEvent();
    }

    subscribeToWalletSyncEvent() {
        if (!this.eventSubscription) {
            const replayId = -1; // -1 for all retained events
            
            this.eventSubscription = subscribe(this.CHANNEL_NAME, replayId, (event) => {
                this.handleWalletSyncEvent(event);
            });
        }
    }

    unsubscribeFromWalletSyncEvent() {
        if (this.eventSubscription) {
            unsubscribe(this.eventSubscription);
            this.eventSubscription = null;
        }
    }

    handleWalletSyncEvent(event) {
        const { WalletId__c } = event.data.payload;
        if (WalletId__c === this.recordId) {
            this.fetchUtxoCounts();
        }
    }

    handleAmountChange(event) {
        const newAmount = event.target.value;
        this.sendAmount = newAmount;
        this.updateSendState();
    }

    handleAddressChange(event) {
        this.sendRecipient = event.target.value;
        this.updateSendState();
    }

    handleMaxAmount() {
        // Set the maximum amount to the current wallet balance
        const maxAmount = parseFloat(this.balance);
        
        if (maxAmount > 0) {
            this.sendAmount = maxAmount.toString();
        } else {
            this.sendAmount = '0';
        }
        this.updateSendState();
    }

    updateSendState() {
        // Basic validation - just enable/disable send button based on input
        const amount = parseFloat(this.sendAmount);
        const hasAmount = !isNaN(amount) && amount > 0;
        const hasRecipient = !!this.sendRecipient && this.sendRecipient.trim() !== '';
        
        // Enable send button if we have both amount and recipient
        this.isSendButtonDisabled = !(hasAmount && hasRecipient);
        this.errorMessage = ''; // Clear any error messages
    }

    async handleSend() {
        // Create the outbound transaction record
        try {
            const transactionId = await createOutboundTransaction({
                walletId: this.recordId,
                toAddress: this.sendRecipient,
                amount: this.sendAmount
            });
            
            this.showToast('Success', 'Outbound transaction created successfully.', 'success');
            
            // Close the modal after successful creation
            this.closeSendModal();
            
        } catch (error) {
            this.showToast('Error', `Failed to create outbound transaction: ${error.body?.message || error.message}`, 'error');
        }
    }



    // Helper method to format numbers with proper decimal places
    formatNumber(value, decimals = 2) {
        if (value === null || value === undefined || isNaN(value)) {
            return '0';
        }
        
        const numValue = parseFloat(value);
        
        // If decimals is specified, use that for all values
        if (decimals !== undefined && decimals !== null) {
            return numValue.toFixed(decimals);
        }
        
        // For very small numbers, show more decimal places
        if (numValue > 0 && numValue < 0.001) {
            return numValue.toFixed(6);
        }
        
        // For numbers less than 1, show 3 decimal places
        if (numValue < 1) {
            return numValue.toFixed(3);
        }
        
        // For larger numbers, show appropriate decimal places
        if (numValue >= 1000000) {
            return (numValue / 1000000).toFixed(2) + 'M';
        } else if (numValue >= 1000) {
            return (numValue / 1000).toFixed(2) + 'K';
        } else {
            return numValue.toFixed(2);
        }
    }
}