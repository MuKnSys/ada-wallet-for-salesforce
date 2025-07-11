import { LightningElement, track, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { loadScript } from 'lightning/platformResourceLoader';
import { subscribe, unsubscribe } from 'lightning/empApi';

import qrcodeLibrary from '@salesforce/resourceUrl/qrcode';

import getWalletAssetSummary from '@salesforce/apex/UTXOAssetController.getWalletAssetSummary';
import getFirstUnusedReceivingAddress from '@salesforce/apex/UTXOController.getFirstUnusedReceivingAddress';
import { MessageContext, APPLICATION_SCOPE } from 'lightning/messageService';
import WALLET_SYNC_CHANNEL from '@salesforce/messageChannel/WalletSyncChannel__c';
import createOutboundTransaction from '@salesforce/apex/TransactionController.createOutboundTransaction';
import getWalletTransactions from '@salesforce/apex/UTXOAssetController.getWalletTransactions';
import getAllUtxoAssetsForWallet from '@salesforce/apex/UTXOAssetController.getAllUtxoAssetsForWallet';
import createMultiAssetOutboundTransaction from '@salesforce/apex/UTXOController.createMultiAssetOutboundTransaction';


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
    @track currentStep = 1;
    @track selectedAsset = 'ADA';
    @track assetOptions = [];
    @track addressError = '';
    @track addressValid = false;
    @track amountError = '';
    @track adaAmount = '';
    @track tokens = [];
    @track tokenOptions = [];
    @track inboundTransactions = [];
    @track outboundTransactions = [];
    @track selectedTransactionType = 'inbound';
    @track sendMemo = '';
    @track showAllInbound = false;
    @track showAllOutbound = false;

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

    // Computed properties for step visibility
    get isStep1() {
        return this.currentStep === 1;
    }

    get isStep2() {
        return this.currentStep === 2;
    }

    get isNextButtonDisabled() {
        return !this.sendRecipient || this.sendRecipient.trim() === '';
    }

    // Step indicator classes
    get step1Class() {
        if (this.currentStep === 1) {
            return 'step active';
        } else if (this.currentStep === 2) {
            return 'step completed';
        }
        return 'step';
    }

    get step2Class() {
        if (this.currentStep === 2) {
            return 'step active';
        }
        return 'step';
    }

    get step1ConnectorClass() {
        if (this.currentStep === 2) {
            return 'step-connector completed';
        }
        return 'step-connector';
    }

    get isInboundSelected() {
        return this.selectedTransactionType === 'inbound';
    }
    get isOutboundSelected() {
        return this.selectedTransactionType === 'outbound';
    }
    handleShowInbound() {
        this.selectedTransactionType = 'inbound';
    }
    handleShowOutbound() {
        this.selectedTransactionType = 'outbound';
    }

    get memoCharCount() {
        return this.sendMemo ? this.sendMemo.length : 0;
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
            // Get asset summary using new method that properly handles ADA conversion
            const summary = await getWalletAssetSummary({ walletId: this.recordId });
            console.log('[WALLET] Asset summary:', summary);
            // Fetch all UTXO assets for the wallet
            const allAssets = await getAllUtxoAssetsForWallet({ walletId: this.recordId });
            console.log('[WALLET] All UTXO assets:', allAssets);
            
            if (summary.success) {
                const tokens = summary.tokens || [];
                const adaBalance = summary.adaBalance || 0;
                
                // Set ADA balance (already converted from lovelace using Value__c field)
                this.balance = this.formatNumber(adaBalance, 6); // ADA uses 6 decimal places

                // Build assets list for tokens (non-ADA assets)
                const assetRows = [];
                tokens.forEach(token => {
                    // Use the actual decimals from the asset metadata, fallback to 0 if not available
                    const assetDecimals = token.decimals !== null && token.decimals !== undefined ? token.decimals : 0;

                    // Determine if icon is a base64 or data URI
                    let imgUrl = null;
                    if (token.icon) {
                        if (token.icon.startsWith('data:image/')) {
                            imgUrl = token.icon;
                        } else if (/^[A-Za-z0-9+/=]+$/.test(token.icon) && token.icon.length > 100) {
                            // Assume base64 string, default to PNG
                            imgUrl = `data:image/png;base64,${token.icon}`;
                        }
                    }

                    assetRows.push({
                        id: token.unit || token.symbol,
                        name: token.name || token.symbol,
                        symbol: token.symbol || token.unit,
                        amount: this.formatNumber(token.amount, assetDecimals), // Use actual asset decimals
                        rawAmount: token.rawAmount, // Keep raw amount for reference
                        decimals: token.decimals,
                        policyId: token.policyId,
                        fingerprint: token.fingerprint,
                        imgUrl: imgUrl,
                        icon: token.icon, // Use icon from Apex only
                        iconIsImage: token.icon && (token.icon.startsWith('data:image') || token.icon.length > 100)
                    });
                });
                
                this.assets = assetRows;
                this.hasAssets = assetRows.length > 0;
            } else {
                this.balance = '0';
                this.assets = [];
                this.hasAssets = false;
            }

            // Fetch payment address
            const payAddr = await getFirstUnusedReceivingAddress({ walletId: this.recordId });
            this.paymentAddress = payAddr ? payAddr : 'No unused address available';
            this.isAddressInvalid = !payAddr;
        } catch (error) {
            const message = error.body?.message || error.message || 'Unknown error';
            this.showToast('Error', message, 'error');
        } finally {
            this.isLoading = false;
            // Fetch transactions after loading assets
            await this.fetchWalletTransactions();
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
        this.adaAmount = '';
        this.tokens = [];
        this.tokenOptions = this.getTokenOptions();
        this.sendRecipient = '';
        this.errorMessage = '';
        this.addressError = '';
        this.addressValid = false;
        this.amountError = '';
        this.isSendButtonDisabled = true;
        this.currentStep = 1;
        this.selectedAsset = 'ADA';
        this.initializeAssetOptions();
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
        if (this.recordId) {
            this.isLoading = true;
            this.fetchUtxoCounts();
        }
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
        const hasAsset = !!this.selectedAsset;
        
        // Enable send button if we have amount, recipient, and asset
        this.isSendButtonDisabled = !(hasAmount && hasRecipient && hasAsset);
        this.errorMessage = ''; // Clear any error messages
    }

    initializeAssetOptions() {
        // Always include ADA as the first option
        const options = [
            { label: 'ADA', value: 'ADA' }
        ];
        
        // Add other assets if available
        if (this.assets && this.assets.length > 0) {
            this.assets.forEach(asset => {
                options.push({
                    label: `${asset.symbol} (${asset.name})`,
                    value: asset.symbol
                });
            });
        }
        
        this.assetOptions = options;
    }

    nextStep() {
        if (this.validateAddress()) {
            this.currentStep = 2;
            this.errorMessage = '';
        }
    }

    previousStep() {
        this.currentStep = 1;
        this.errorMessage = '';
    }

    handleAssetChange(event) {
        this.selectedAsset = event.detail.value;
        this.updateSendState();
    }

    validateAddress() {
        const address = this.sendRecipient.trim();
        
        if (!address) {
            this.addressError = 'Recipient address is required';
            this.addressValid = false;
            return false;
        }
        
        // Basic Cardano address validation (starts with addr1, addr_test1, etc.)
        const cardanoAddressPattern = /^addr[1-9][a-z0-9]{98}$/;
        const testAddressPattern = /^addr_test[1-9][a-z0-9]{98}$/;
        
        if (!cardanoAddressPattern.test(address) && !testAddressPattern.test(address)) {
            this.addressError = 'Please enter a valid Cardano address';
            this.addressValid = false;
            return false;
        }
        
        this.addressError = '';
        this.addressValid = true;
        return true;
    }

    validateAmount() {
        const amount = parseFloat(this.sendAmount);
        
        if (!this.sendAmount || this.sendAmount.trim() === '') {
            this.amountError = 'Amount is required';
            return false;
        }
        
        if (isNaN(amount) || amount <= 0) {
            this.amountError = 'Please enter a valid amount greater than 0';
            return false;
        }
        
        // Check if amount exceeds available balance
        const availableBalance = parseFloat(this.balance) || 0;
        if (amount > availableBalance) {
            this.amountError = `Insufficient balance. Available: ${availableBalance} ADA`;
            return false;
        }
        
        this.amountError = '';
        return true;
    }

    updateSendStateMultiAsset() {
        console.log('[DEBUG] updateSendStateMultiAsset called');
        console.log(`[DEBUG] adaAmount: ${this.adaAmount}`);
        console.log(`[DEBUG] tokens:`, this.tokens);
        // ADA validation
        const adaAvailable = parseFloat(this.balance);
        const adaValid = !!this.adaAmount && parseFloat(this.adaAmount) > 0 && parseFloat(this.adaAmount) <= adaAvailable;
        console.log(`[DEBUG] ADA: amount=${this.adaAmount}, available=${adaAvailable}, valid=${adaValid}`);
        // Token validation
        let tokensValid = false;
        if (this.tokens.length > 0) {
            tokensValid = this.tokens.every(token => {
                if (!token.asset || !token.amount) {
                    console.log(`[DEBUG] Token row invalid: asset=${token.asset}, amount=${token.amount}`);
                    return false;
                }
                const asset = this.assets.find(a => a.symbol === token.asset);
                if (!asset) {
                    console.log(`[DEBUG] Token asset not found: ${token.asset}`);
                    return false;
                }
                const amount = parseFloat(token.amount);
                const valid = amount > 0 && amount <= parseFloat(asset.amount);
                console.log(`[DEBUG] Token: asset=${token.asset}, amount=${token.amount}, available=${asset.amount}, valid=${valid}`);
                return valid;
            });
        }
        // Recipient validation
        const hasRecipient = !!this.sendRecipient && this.sendRecipient.trim() !== '' && this.addressValid;
        console.log(`[DEBUG] Recipient: value=${this.sendRecipient}, valid=${this.addressValid}`);
        // Enable send button if recipient is valid AND (ADA is valid OR (at least one token and all tokens valid))
        const enable = hasRecipient && (adaValid || tokensValid);
        this.isSendButtonDisabled = !enable;
        console.log(`[DEBUG] isSendButtonDisabled=${this.isSendButtonDisabled} (hasRecipient=${hasRecipient}, adaValid=${adaValid}, tokensValid=${tokensValid})`);
    }

    async handleSend() {
        if (this.isSendButtonDisabled) return;
        this.isLoading = true;
        try {
            // Build the assets array for multi-asset transactions
            const assetsArray = [];
            if (this.adaAmount && parseFloat(this.adaAmount) > 0) {
                assetsArray.push({ asset: 'ADA', amount: this.adaAmount });
            }
            this.tokens.forEach(token => {
                if (token.asset && token.amount && parseFloat(token.amount) > 0) {
                    assetsArray.push({ asset: token.asset, amount: token.amount });
                }
            });
            console.log('[SEND] Assets array to send:', JSON.stringify(assetsArray));
            console.log('[SEND] Recipient:', this.sendRecipient);
            // If more than one asset, use multi-asset Apex method
            if (assetsArray.length > 1) {
                console.log('[SEND] Calling createMultiAssetOutboundTransaction Apex method');
                const outboundId = await createMultiAssetOutboundTransaction({
                    walletId: this.recordId,
                    toAddress: this.sendRecipient,
                    assets: assetsArray,
                    memo: this.sendMemo
                });
                console.log('[SEND] Apex returned outboundId:', outboundId);
                this.showToast('Success', 'Multi-asset transaction created successfully!', 'success');
            } else if (assetsArray.length === 1) {
                console.log('[SEND] Calling createOutboundTransaction Apex method');
                const outboundId = await createOutboundTransaction({
                    walletId: this.recordId,
                    toAddress: this.sendRecipient,
                    amount: assetsArray[0].amount,
                    asset: assetsArray[0].asset,
                    memo: this.sendMemo
                });
                console.log('[SEND] Apex returned outboundId:', outboundId);
                this.showToast('Success', 'Transaction created successfully!', 'success');
            } else {
                this.showToast('Error', 'No valid assets to send.', 'error');
                return;
            }
            this.showSend = false;
            this.fetchUtxoCounts();
        } catch (error) {
            console.error('[SEND] Error from Apex:', error);
            this.showToast('Error', error.body?.message || error.message || 'Failed to create transaction', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async fetchWalletTransactions() {
        try {
            const result = await getWalletTransactions({ walletId: this.recordId });
            console.log('[WALLET] Transactions:', result);
            this.inboundTransactions = result.inbound || [];
            this.outboundTransactions = result.outbound || [];
        } catch (error) {
            this.inboundTransactions = [];
            this.outboundTransactions = [];
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

    getTokenOptions() {
        // Exclude ADA, show only symbol and name in label
        return this.assets
            .filter(asset => asset.symbol !== 'ADA')
            .map(asset => ({
                label: `${asset.symbol} (${asset.name})`,
                value: asset.symbol
            }));
    }

    getTokenAvailableAmount(tokenSymbol) {
        const asset = this.assets.find(a => a.symbol === tokenSymbol);
        return asset ? parseFloat(asset.amount) : 0;
    }

    getTokenDecimals(tokenSymbol) {
        const asset = this.assets.find(a => a.symbol === tokenSymbol);
        return asset && asset.decimals !== undefined ? asset.decimals : 0;
    }

    getTokenAmountWarning(token) {
        if (!token.asset || !token.amount) return '';
        const available = this.getTokenAvailableAmount(token.asset);
        const entered = parseFloat(token.amount);
        if (entered > available) {
            return `Exceeds available: ${this.formatNumber(available, this.getTokenDecimals(token.asset))}`;
        }
        return '';
    }

    get safeTokens() {
        return Array.isArray(this.tokens) ? this.tokens : [];
    }

    handleAdaAmountChange(event) {
        this.adaAmount = event.target.value;
        this.updateSendStateMultiAsset();
    }

    addToken() {
        // Prevent adding duplicate token rows for the same asset
        const usedTickers = this.tokens.map(t => t.asset).filter(Boolean);
        const availableOptions = this.tokenOptions.filter(opt => !usedTickers.includes(opt.value));
        if (availableOptions.length === 0) {
            this.showToast('Info', 'All tokens already added.', 'info');
            return;
        }
        // Add a new row with empty asset and id for now
        this.tokens = [
            ...this.tokens,
            { id: '', asset: '', amount: '', available: '', warning: '', placeholder: '' }
        ];
        this.updateSendStateMultiAsset();
    }

    removeToken(event) {
        const index = parseInt(event.target.dataset.index, 10);
        this.tokens = this.tokens.filter((_, i) => i !== index);
        this.updateTokenComputedFields();
        this.updateSendStateMultiAsset();
    }

    handleTokenChange(event) {
        const index = parseInt(event.target.dataset.index, 10);
        const value = event.detail.value;
        this.tokens = this.tokens.map((token, i) =>
            i === index ? { ...token, asset: value, id: value } : token
        );
        this.updateTokenComputedFields();
        this.updateSendStateMultiAsset();
    }

    handleTokenAmountChange(event) {
        const index = parseInt(event.target.dataset.index, 10);
        const value = event.target.value;
        this.tokens = this.tokens.map((token, i) =>
            i === index ? { ...token, amount: value } : token
        );
        this.updateTokenComputedFields();
        this.updateSendStateMultiAsset();
    }

    updateTokenComputedFields() {
        this.tokens = this.tokens.map(token => {
            let available = '';
            let warning = '';
            let placeholder = '';
            if (token.asset) {
                const asset = this.assets.find(a => a.symbol === token.asset);
                if (asset) {
                    available = this.formatNumber(asset.amount, asset.decimals);
                    if (!token.amount) {
                        placeholder = available;
                    }
                    if (token.amount && parseFloat(token.amount) > parseFloat(asset.amount)) {
                        warning = `Exceeds available: ${available}`;
                    }
                }
            }
            return { ...token, available, warning, placeholder };
        });
    }



    handleSendMaxToken(event) {
        const index = parseInt(event.target.dataset.index, 10);
        const token = this.tokens[index];
        if (!token || !token.asset) return;
        const available = this.getTokenAvailableAmount(token.asset);
        const decimals = this.getTokenDecimals(token.asset);
        this.tokens = this.tokens.map((t, i) =>
            i === index ? { ...t, amount: available.toFixed(decimals) } : t
        );
        this.updateTokenComputedFields();
        this.updateSendStateMultiAsset();
    }

    handleTransactionTabChange(event) {
        this.selectedTransactionType = event.target.value;
    }

    get outboundTransactionsWithUrl() {
        return (this.outboundTransactions || []).map(tx => ({
            ...tx,
            cardanoScanUrl: tx.Transaction_Hash__c ? `https://cardanoscan.io/transaction/${tx.Transaction_Hash__c}` : null
        }));
    }

    get outboundTransactionsForDisplay() {
        // Always provide Transaction_Hash__c, Transaction_Status__c, and cardanoScanUrl for template
        return this.visibleOutboundTransactions.map(tx => {
            const hash = tx.Transaction_Hash__c;
            let cardanoScanUrl = '';
            if (hash && typeof hash === 'string' && hash.length > 0) {
                cardanoScanUrl = `https://cardanoscan.io/transaction/${hash}`;
            }
            return {
                ...tx,
                Transaction_Hash__c: hash,
                Transaction_Status__c: tx.Transaction_Status__c || '',
                cardanoScanUrl
            };
        });
    }

    handleAssetImgError(event) {
        const symbol = event.target.alt;
        this.assets = this.assets.map(asset => {
            if (asset.symbol === symbol) {
                return { ...asset, showFallbackIcon: true, icon: 'utility:money', imgUrl: null, iconIsImage: false };
            }
            return asset;
        });
    }

    handleMemoChange(event) {
        this.sendMemo = event.target.value;
        console.log('[WALLET] Memo changed:', this.sendMemo);
        console.log('[WALLET] Memo length:', this.sendMemo.length);
    }

    get sortedInboundTransactions() {
        return [...this.inboundTransactions].sort((a, b) => new Date(b.CreatedDate) - new Date(a.CreatedDate));
    }
    get sortedOutboundTransactions() {
        return [...this.outboundTransactions].sort((a, b) => new Date(b.CreatedDate) - new Date(a.CreatedDate));
    }
    get visibleInboundTransactions() {
        return this.showAllInbound ? this.sortedInboundTransactions : this.sortedInboundTransactions.slice(0, 3);
    }
    get visibleOutboundTransactions() {
        return this.showAllOutbound ? this.sortedOutboundTransactions : this.sortedOutboundTransactions.slice(0, 3);
    }
    handleViewAllInbound() {
        this.showAllInbound = true;
    }
    handleViewAllOutbound() {
        this.showAllOutbound = true;
    }
    formatDate(dateString) {
        if (!dateString) return '';
        const date = new Date(dateString);
        return date.toLocaleString('en-US', {
            year: 'numeric', month: 'short', day: '2-digit',
            hour: '2-digit', minute: '2-digit', hour12: true
        });
    }

    get inboundHasMore() {
        return this.sortedInboundTransactions.length > 3 && !this.showAllInbound;
    }
    get outboundHasMore() {
        return this.sortedOutboundTransactions.length > 3 && !this.showAllOutbound;
    }

    // When preparing transactions for display, add formattedDate property
    set inboundTransactions(value) {
        this._inboundTransactions = (value || []).map(tx => ({
            ...tx,
            formattedDate: this.formatDate(tx.CreatedDate)
        }));
    }
    get inboundTransactions() {
        return this._inboundTransactions || [];
    }
    set outboundTransactions(value) {
        this._outboundTransactions = (value || []).map(tx => ({
            ...tx,
            formattedDate: this.formatDate(tx.CreatedDate)
        }));
    }
    get outboundTransactions() {
        return this._outboundTransactions || [];
    }
}