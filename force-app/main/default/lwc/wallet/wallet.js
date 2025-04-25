import { LightningElement, track, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { loadScript } from 'lightning/platformResourceLoader';
import getPaymentAddress from '@salesforce/apex/WalletCtrl.getPaymentAddress';
import getWalletTotalBalance from '@salesforce/apex/WalletCtrl.getWalletTotalBalance';
import qrcodeLibrary from '@salesforce/resourceUrl/qrcode';

export default class Wallet extends LightningElement {
    _recordId;
    @track balance = null;
    @track paymentAddress = 'Loading payment address...';
    @track showReceive = false;
    @track showSend = false;
    @track isLoading = false;
    @track isAddressInvalid = false;
    @track balanceRetryCount = 0;
    @track maxBalanceRetries = 3;
    @track isQrCodeLibraryLoaded = false;
    @track qrCodeError = false;

    @api
    get recordId() {
        return this._recordId;
    }

    set recordId(value) {
        const recordIdChanged = this._recordId != value;
        this._recordId = value;

        if (this._recordId != null && recordIdChanged) {
            this.initializeWallet();
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

    async initializeWallet() {
        this.isLoading = true;
        try {
            await Promise.all([
                this.fetchPaymentAddress(),
                this.fetchWalletBalance()
            ]);
        } catch (error) {
            this.showToast('Error', error.body?.message || error.message || 'Unknown error initializing wallet', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async fetchPaymentAddress() {
        this.isAddressInvalid = false;
        try {
            this.paymentAddress = await getPaymentAddress({ walletId: this.recordId });
            this.qrCodeError = false;
        } catch (error) {
            this.paymentAddress = 'Not available: Unable to fetch payment address';
            this.isAddressInvalid = true;
            this.showToast('Error', error.body?.message || error.message || 'Unknown error fetching payment address', 'error');
        }
    }

    async fetchWalletBalance() {
        try {
            const result = await getWalletTotalBalance({ walletId: this.recordId });
            const totalBalance = result.totalBalance || {};
            let adaBalance = 0;
            if (totalBalance.lovelace) {
                adaBalance = totalBalance.lovelace / 1000000; // Convert lovelace to ADA
            }
            this.balance = adaBalance.toFixed(6); // Display with 6 decimal places
            this.balanceRetryCount = 0; // Reset retry count on success
        } catch (error) {
            this.balanceRetryCount++;
            let errorMessage = error.body?.message || error.message || 'Unknown error fetching wallet balance';
            if (errorMessage.includes('Blockfrost Project ID is not set or found')) {
                this.balance = null;
                this.showToast('Error', 'Blockfrost Project ID is not configured. Please contact your administrator.', 'error');
            } else if (this.balanceRetryCount < this.maxBalanceRetries) {
                setTimeout(() => this.fetchWalletBalance(), 2000);
            } else {
                this.balance = null;
                this.showToast('Error', `${errorMessage} after retries`, 'error');
            }
        }
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
                // Clear previous QR code
                qrCodeElement.innerHTML = '';
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
        this.showSend = true;
    }

    closeSendModal() {
        this.showSend = false;
    }

    copyToClipboard() {
        if (this.paymentAddress && !this.isAddressInvalid) {
            navigator.clipboard.writeText(this.paymentAddress).then(() => {
                this.showToast('Success', 'Address copied to clipboard', 'success');
            }).catch(error => {
                this.showToast('Error', 'Failed to copy address to clipboard', 'error');
            });
        } else {
            this.showToast('Error', 'No valid address to copy', 'error');
        }
    }

    shareLink() {
        if (this.paymentAddress && !this.isAddressInvalid) {
            const canvas = this.template.querySelector('.qr-code-canvas canvas');
            if (canvas) {
                const url = canvas.toDataURL('image/png');
                const link = document.createElement('a');
                link.href = url;
                link.download = 'qr-code.png';
                link.click();
            } else {
                this.showToast('Error', 'QR code not generated yet.', 'error');
            }
        } else {
            this.showToast('Error', 'No valid address to share', 'error');
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
}