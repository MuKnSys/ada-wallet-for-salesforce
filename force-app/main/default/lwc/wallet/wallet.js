import { LightningElement, track, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { loadScript } from 'lightning/platformResourceLoader';
import getPaymentAddress from '@salesforce/apex/AdaWalletCtrl.getPaymentAddress';
import getWalletTotalBalance from '@salesforce/apex/BlockfrostConnector.getWalletTotalBalance';
import qrcodeLibrary from '@salesforce/resourceUrl/qrcode';

export default class Wallet extends LightningElement {
    _recordId; // Private backing field for recordId
    @track balance = null; // Initialize as null until fetched
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
        console.log(`Wallet [${new Date().toISOString()}]: recordId setter called with value: ${value}`);
        this._recordId = value;
        if (value && /^[a-zA-Z0-9]{15,18}$/.test(value) && !this.isLoading) {
            console.log(`Wallet [${new Date().toISOString()}]: Valid recordId set, triggering initialization`);
            this.initializeWallet();
        }
    }

    connectedCallback() {
        console.log(`Wallet [${new Date().toISOString()}]: connectedCallback - Record ID: ${this.recordId}`);
        console.log(`Wallet [${new Date().toISOString()}]: Window location: ${window.location.href}`);
        this.loadQrCodeLibrary();
        if (this.recordId && /^[a-zA-Z0-9]{15,18}$/.test(this.recordId)) {
            console.log(`Wallet [${new Date().toISOString()}]: Valid recordId in connectedCallback, initializing wallet`);
            this.initializeWallet();
        } else {
            console.warn(`Wallet [${new Date().toISOString()}]: No valid recordId in connectedCallback. Waiting for setter or retrying in renderedCallback.`);
            const url = window.location.href;
            const match = url.match(/Wallet__c\/([a-zA-Z0-9]{15,18})/);
            if (match) {
                console.log(`Wallet [${new Date().toISOString()}]: Extracted recordId from URL: ${match[1]}`);
                this._recordId = match[1];
                this.initializeWallet();
            }
        }
    }

    async loadQrCodeLibrary() {
        if (this.isQrCodeLibraryLoaded) {
            return;
        }

        try {
            await loadScript(this, qrcodeLibrary);
            this.isQrCodeLibraryLoaded = true;
            console.log(`Wallet [${new Date().toISOString()}]: QR Code library loaded successfully`);
        } catch (error) {
            console.error(`Wallet [${new Date().toISOString()}]: Error loading QR Code library:`, error);
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
        console.log(`Wallet [${new Date().toISOString()}]: renderedCallback - Record ID: ${this.recordId}, isLoading: ${this.isLoading}, paymentAddress: ${this.paymentAddress}, balance: ${this.balance}`);
        if (!this.isLoading && !this.paymentAddress.startsWith('addr') && this.recordId && /^[a-zA-Z0-9]{15,18}$/.test(this.recordId)) {
            console.log(`Wallet [${new Date().toISOString()}]: Valid recordId in renderedCallback, retrying initialization`);
            this.initializeWallet();
        }
        // Generate QR code in the canvas when the modal is opened
        if (this.showReceive && this.isQrCodeLibraryLoaded && this.paymentAddress && !this.isAddressInvalid && !this.qrCodeError) {
            this.generateQrCode();
        }
    }

    async initializeWallet() {
        if (this.isLoading) {
            console.log(`Wallet [${new Date().toISOString()}]: initializeWallet skipped - already loading`);
            return;
        }

        this.isLoading = true;
        try {
            console.log(`Wallet [${new Date().toISOString()}]: Initializing wallet with recordId: ${this.recordId}`);
            await Promise.all([
                this.fetchPaymentAddress(),
                this.fetchWalletBalance()
            ]);
        } catch (error) {
            console.error(`Wallet [${new Date().toISOString()}]: Error initializing wallet:`, error);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: error.body?.message || error.message || 'Unknown error initializing wallet',
                    variant: 'error'
                })
            );
        } finally {
            this.isLoading = false;
            console.log(`Wallet [${new Date().toISOString()}]: initializeWallet completed - isLoading: ${this.isLoading}`);
        }
    }

    async fetchPaymentAddress() {
        this.isAddressInvalid = false;
        try {
            console.log(`Wallet [${new Date().toISOString()}]: fetchPaymentAddress - Validating recordId: ${this.recordId}`);
            if (!this.recordId || !/^[a-zA-Z0-9]{15,18}$/.test(this.recordId)) {
                console.error(`Wallet [${new Date().toISOString()}]: Invalid or missing recordId for payment address: ${this.recordId}`);
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

            console.log(`Wallet [${new Date().toISOString()}]: Fetching payment address for Wallet__c ID: ${this.recordId}`);
            this.paymentAddress = await getPaymentAddress({ walletId: this.recordId });
            console.log(`Wallet [${new Date().toISOString()}]: Payment address retrieved: ${this.paymentAddress}`);
            this.qrCodeError = false; // Reset QR code error on successful fetch
        } catch (error) {
            console.error(`Wallet [${new Date().toISOString()}]: Error fetching payment address:`, error);
            console.error(`Wallet [${new Date().toISOString()}]: Error details:`, JSON.stringify(error, null, 2));
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
            console.log(`Wallet [${new Date().toISOString()}]: fetchWalletBalance - Validating recordId: ${this.recordId}`);
            if (!this.recordId || !/^[a-zA-Z0-9]{15,18}$/.test(this.recordId)) {
                console.error(`Wallet [${new Date().toISOString()}]: Invalid or missing recordId for balance: ${this.recordId}`);
                this.balance = null;
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: 'Invalid Wallet ID for balance fetch.',
                        variant: 'error'
                    })
                );
                return;
            }

            console.log(`Wallet [${new Date().toISOString()}]: Fetching wallet balance for Wallet__c ID: ${this.recordId} (Attempt ${this.balanceRetryCount + 1}/${this.maxBalanceRetries})`);
            const result = await getWalletTotalBalance({ walletId: this.recordId });
            console.log(`Wallet [${new Date().toISOString()}]: Wallet balance result:`, JSON.stringify(result, null, 2));

            const addressDetails = result.addressDetails || {};
            console.log(`Wallet [${new Date().toISOString()}]: === UTXO Addresses for Wallet__c ID: ${this.recordId} ===`);
            for (const address in addressDetails) {
                const details = addressDetails[address];
                console.log(`Wallet [${new Date().toISOString()}]: Address: ${address}`);
                console.log(`Wallet [${new Date().toISOString()}]: Type: ${details.type === '0' ? 'Receiving' : 'Change'}`);
                console.log(`Wallet [${new Date().toISOString()}]: Transaction Count: ${details.tx_count}`);
                console.log(`Wallet [${new Date().toISOString()}]: Received Assets:`, JSON.stringify(details.received_sum, null, 2));
                console.log(`Wallet [${new Date().toISOString()}]: Sent Assets:`, JSON.stringify(details.sent_sum, null, 2));
                console.log(`Wallet [${new Date().toISOString()}]: ---`);
            }
            console.log(`Wallet [${new Date().toISOString()}]: =============================`);

            const totalBalance = result.totalBalance || {};
            let adaBalance = 0;
            if (totalBalance.lovelace) {
                adaBalance = totalBalance.lovelace / 1000000; // Convert lovel reis to ADA
                console.log(`Wallet [${new Date().toISOString()}]: Total ADA Balance: ${adaBalance} ADA`);
            } else {
                console.log(`Wallet [${new Date().toISOString()}]: No ADA balance found for wallet`);
            }

            for (const unit in totalBalance) {
                if (unit !== 'lovelace') {
                    console.log(`Wallet [${new Date().toISOString()}]: Asset ${unit}: ${totalBalance[unit]} units`);
                }
            }

            this.balance = adaBalance.toFixed(6); // Display with 6 decimal places
            console.log(`Wallet [${new Date().toISOString()}]: Updated UI balance: ${this.balance} ADA`);
            this.balanceRetryCount = 0; // Reset retry count on success
        } catch (error) {
            console.error(`Wallet [${new Date().toISOString()}]: Error fetching wallet balance:`, error);
            console.error(`Wallet [${new Date().toISOString()}]: Error details:`, JSON.stringify(error, null, 2));
            this.balanceRetryCount++;
            let errorMessage = error.body?.message || error.message || 'Unknown error fetching wallet balance';
            if (errorMessage.includes('Blockfrost Project ID is not set or found')) {
                console.error(`Wallet [${new Date().toISOString()}]: Blockfrost Project ID missing, no retries needed`);
                this.balance = null;
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: 'Blockfrost Project ID is not configured. Please contact your administrator.',
                        variant: 'error'
                    })
                );
            } else if (this.balanceRetryCount < this.maxBalanceRetries) {
                console.log(`Wallet [${new Date().toISOString()}]: Retrying fetchWalletBalance in 2 seconds (Attempt ${this.balanceRetryCount + 1}/${this.maxBalanceRetries})`);
                setTimeout(() => this.fetchWalletBalance(), 2000);
            } else {
                console.error(`Wallet [${new Date().toISOString()}]: Max retries reached for fetchWalletBalance`);
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
            console.error(`Wallet [${new Date().toISOString()}]: Error generating QR code:`, error);
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
                console.error(`Wallet [${new Date().toISOString()}]: Error copying to clipboard:`, error);
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