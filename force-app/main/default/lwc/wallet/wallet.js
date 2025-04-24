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

    connectedCallback() {
        this.loadQrCodeLibrary();
    }

    async loadQrCodeLibrary() {
        if (this.isQrCodeLibraryLoaded) {
            return;
        }

        try {
            await loadScript(this, qrcodeLibrary);
            this.isQrCodeLibraryLoaded = true;
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: 'Failed to load QR Code library.',
                    variant: 'error'
                })
            );
        }
    }

    renderedCallback() {
        if (this.showReceive && this.isQrCodeLibraryLoaded && this.paymentAddress && !this.isAddressInvalid && !this.qrCodeError) {
            this.generateQrCode();
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
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: error.body?.message || error.message || 'Unknown error initializing wallet',
                    variant: 'error'
                })
            );
        } finally {
            this.isLoading = false;
        }
    }

    async fetchPaymentAddress() {
        this.isAddressInvalid = false;
        try {
            if (!this.recordId || !/^[a-zA-Z0-9]{15,18}$/.test(this.recordId)) {
                this.paymentAddress = 'Not available: Invalid Wallet ID';
                this.isAddressInvalid = true;
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: 'Invalid Wallet ID for payment address.',
                        variant: 'error'
                    })
                );
                return;
            }
            
            this.paymentAddress = await getPaymentAddress({ walletId: this.recordId });
            this.qrCodeError = false;
        } catch (error) {
            this.paymentAddress = 'Not available: Unable to fetch payment address';
            this.isAddressInvalid = true;
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: error.body?.message || error.message || 'Unknown error fetching payment address',
                    variant: 'error'
                })
            );
        }
    }

    async fetchWalletBalance() {
        try {
            const result = await getWalletTotalBalance({ walletId: this.recordId });
            const totalBalance = result.totalBalance || {};
            let adaBalance = 0;
            if (totalBalance.lovelace) {
                adaBalance = totalBalance.lovelace / 1000000; // Convert lovel reis to ADA
            }
            this.balance = adaBalance.toFixed(6); // Display with 6 decimal places
            this.balanceRetryCount = 0; // Reset retry count on success
        } catch (error) {
            this.balanceRetryCount++;
            let errorMessage = error.body?.message || error.message || 'Unknown error fetching wallet balance';
            if (errorMessage.includes('Blockfrost Project ID is not set or found')) {
                this.balance = null;
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: 'Blockfrost Project ID is not configured. Please contact your administrator.',
                        variant: 'error'
                    })
                );
            } else if (this.balanceRetryCount < this.maxBalanceRetries) {
                setTimeout(() => this.fetchWalletBalance(), 2000);
            } else {
                this.balance = null;
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: errorMessage + ' after retries',
                        variant: 'error'
                    })
                );
            }
        }
    }

    generateQrCode() {
        if (!this.isQrCodeLibraryLoaded || !this.paymentAddress || this.isAddressInvalid) {
            this.qrCodeError = true;
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: 'Cannot generate QR code: Invalid address or library not loaded.',
                    variant: 'error'
                })
            );
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
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: 'Failed to generate QR code.',
                    variant: 'error'
                })
            );
        }
    }

    openReceiveModal() {
        if (this.isAddressInvalid) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: 'Cannot open Receive modal: No valid payment address available.',
                    variant: 'error'
                })
            );
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
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Success',
                        message: 'Address copied to clipboard',
                        variant: 'success'
                    })
                );
            }).catch(error => {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: 'Failed to copy address to clipboard',
                        variant: 'error'
                    })
                );
            });
        } else {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: 'No valid address to copy',
                    variant: 'error'
                })
            );
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
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: 'QR code not generated yet.',
                        variant: 'error'
                    })
                );
            }
        } else {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: 'No valid address to share',
                    variant: 'error'
                })
            );
        }
    }
}