import { LightningElement, track, api } from 'lwc';
import { loadScript } from 'lightning/platformResourceLoader';
import { subscribe, unsubscribe } from 'lightning/empApi';

import qrcodeLibrary from '@salesforce/resourceUrl/qrcode';

import getWalletAssetSummary from '@salesforce/apex/UTXOAssetController.getWalletAssetSummary';
import getFirstUnusedReceivingAddress from '@salesforce/apex/UTXOController.getFirstUnusedReceivingAddress';
import createOutboundTransaction from '@salesforce/apex/TransactionController.createOutboundTransaction';
// import getWalletTransactions from '@salesforce/apex/UTXOAssetController.getWalletTransactions';
// import getAllUtxoAssetsForWallet from '@salesforce/apex/UTXOAssetController.getAllUtxoAssetsForWallet';
import createMultiAssetOutboundTransaction from '@salesforce/apex/UTXOController.createMultiAssetOutboundTransaction';
import { showToast } from 'c/utils';

export default class Wallet extends LightningElement {
    CHANNEL_NAME = '/event/WalletSyncEvent__e';

    _recordId;
    _inboundTransactions = [];
    _outboundTransactions = [];
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

    get isStep1() {
        return this.currentStep === 1;
    }

    get isStep2() {
        return this.currentStep === 2;
    }

    get isNextButtonDisabled() {
        return !this.sendRecipient || this.sendRecipient.trim() === '';
    }

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

    get memoCharCount() {
        return this.sendMemo ? this.sendMemo.length : 0;
    }

    get safeTokens() {
        return Array.isArray(this.tokens) ? this.tokens : [];
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

    get inboundHasMore() {
        return this.sortedInboundTransactions.length > 3 && !this.showAllInbound;
    }

    get outboundHasMore() {
        return this.sortedOutboundTransactions.length > 3 && !this.showAllOutbound;
    }

    get outboundTransactionsWithUrl() {
        return (this.outboundTransactions || []).map(tx => ({
            ...tx,
            cardanoScanUrl: tx.Transaction_Hash__c ? `https://cardanoscan.io/transaction/${tx.Transaction_Hash__c}` : null
        }));
    }

    get outboundTransactionsForDisplay() {
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

    async renderedCallback() {
        if (!this.isQrCodeLibraryLoaded) {            
            await this.loadQrCodeLibrary();
        }

        if (this.showReceive && this.isQrCodeLibraryLoaded && this.paymentAddress && !this.isAddressInvalid && !this.qrCodeError) {
            this.generateQrCode();
        }
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
    
    async loadQrCodeLibrary() {
        try {
            await loadScript(this, qrcodeLibrary);
            this.isQrCodeLibraryLoaded = true;
        } catch (error) {
            showToast(this, 'Error', 'Failed to load QR Code library.', 'error');
        }
    }
    
    async fetchUtxoCounts() {
        try {
            const summary = await getWalletAssetSummary({ walletId: this.recordId });
            const allAssets = await this.getAllUtxoAssetsForWallet({ walletId: this.recordId });
            
            if (summary.success) {
                const tokens = summary.tokens || [];
                const adaBalance = summary.adaBalance || 0;
                
                this.balance = this.formatNumber(adaBalance, 6);

                const assetRows = [];
                tokens.forEach(token => {
                    const assetDecimals = token.decimals !== null && token.decimals !== undefined ? token.decimals : 0;

                    let imgUrl = null;
                    if (token.icon) {
                        if (token.icon.startsWith('data:image/')) {
                            imgUrl = token.icon;
                        } else if (/^[A-Za-z0-9+/=]+$/.test(token.icon) && token.icon.length > 100) {
                            imgUrl = `data:image/png;base64,${token.icon}`;
                        }
                    }

                    assetRows.push({
                        id: token.unit || token.symbol,
                        name: token.name || token.symbol,
                        symbol: token.symbol || token.unit,
                        amount: this.formatNumber(token.amount, assetDecimals),
                        rawAmount: token.rawAmount,
                        decimals: token.decimals,
                        policyId: token.policyId,
                        fingerprint: token.fingerprint,
                        imgUrl: imgUrl,
                        icon: token.icon,
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

            const payAddr = await getFirstUnusedReceivingAddress({ walletId: this.recordId });
            this.paymentAddress = payAddr ? payAddr : 'No unused address available';
            this.isAddressInvalid = !payAddr;
        } catch (error) {
            const message = error.body?.message || error.message || 'Unknown error';
            showToast(this, 'Error', message, 'error');
        } finally {
            this.isLoading = false;
            await this.fetchWalletTransactions();
        }
    }

    async fetchWalletTransactions() {
        try {
            const result = await getWalletTransactions({ walletId: this.recordId });
            this._inboundTransactions = result.inbound || [];
            this._outboundTransactions = result.outbound || [];
        } catch (error) {
            this._inboundTransactions = [];
            this._outboundTransactions = [];
        }
    }

    // Temporary dummy functions to replace missing Apex methods
    async getWalletTransactions(params) {
        return { success: true, transactions: [], message: 'Method not yet implemented' };
    }
    
    async getAllUtxoAssetsForWallet(params) {
        return { success: true, assets: [], message: 'Method not yet implemented' };
    }
    
    generateQrCode() {
        if (!this.isQrCodeLibraryLoaded || !this.paymentAddress || this.isAddressInvalid) {
            this.qrCodeError = true;
            showToast(this, 'Error', 'Cannot generate QR code: Invalid address or library not loaded.', 'error');
            return;
        }

        try {
            const qrCodeElement = this.template.querySelector('.qr-code-canvas');
            if (qrCodeElement) {
                while (qrCodeElement.firstChild) {
                    qrCodeElement.removeChild(qrCodeElement.firstChild);
                }
                
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
            showToast(this, 'Error', 'Failed to generate QR code.', 'error');
        }
    }
    
    openReceiveModal() {
        if (this.isAddressInvalid) {
            showToast(this, 'Error', 'Cannot open Receive modal: No valid payment address available.', 'error');
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
                showToast(this, 'Success', 'Address copied to clipboard!', 'success');
            }).catch(() => {
                showToast(this, 'Error', 'Failed to copy address to clipboard.', 'error');
            });
        } else {
            const textArea = document.createElement('textarea');
            textArea.value = this.paymentAddress;
            document.body.appendChild(textArea);
            textArea.select();
            try {
                document.execCommand('copy');
                showToast(this, 'Success', 'Address copied to clipboard!', 'success');
            } catch (err) {
                showToast(this, 'Error', 'Failed to copy address to clipboard.', 'error');
            }
            document.body.removeChild(textArea);
        }
    }

    shareLink() {
        showToast(this, 'Info', 'QR Code download functionality not implemented yet.', 'info');
    }
    
    handleShowInbound() {
        this.selectedTransactionType = 'inbound';
    }
    
    handleShowOutbound() {
        this.selectedTransactionType = 'outbound';
    }

    handleTransactionTabChange(event) {
        this.selectedTransactionType = event.target.value;
    }

    handleViewAllInbound() {
        this.showAllInbound = true;
    }

    handleViewAllOutbound() {
        this.showAllOutbound = true;
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
        const maxAmount = parseFloat(this.balance);
        
        if (maxAmount > 0) {
            this.sendAmount = maxAmount.toString();
        } else {
            this.sendAmount = '0';
        }
        this.updateSendState();
    }

    updateSendState() {
        const amount = parseFloat(this.sendAmount);
        const hasAmount = !isNaN(amount) && amount > 0;
        const hasRecipient = !!this.sendRecipient && this.sendRecipient.trim() !== '';
        const hasAsset = !!this.selectedAsset;
        
        this.isSendButtonDisabled = !(hasAmount && hasRecipient && hasAsset);
        this.errorMessage = '';
    }

    updateSendStateMultiAsset() {
        const adaAvailable = parseFloat(this.balance);
        const adaValid = !!this.adaAmount && parseFloat(this.adaAmount) > 0 && parseFloat(this.adaAmount) <= adaAvailable;
        
        let tokensValid = false;
        if (this.tokens.length > 0) {
            tokensValid = this.tokens.every(token => {
                if (!token.asset || !token.amount) {
                    return false;
                }
                const asset = this.assets.find(a => a.symbol === token.asset);
                if (!asset) {
                    return false;
                }
                const amount = parseFloat(token.amount);
                const valid = amount > 0 && amount <= parseFloat(asset.amount);
                return valid;
            });
        }
        
        const hasRecipient = !!this.sendRecipient && this.sendRecipient.trim() !== '' && this.addressValid;
        
        const enable = hasRecipient && (adaValid || tokensValid);
        this.isSendButtonDisabled = !enable;
    }

    async handleSend() {
        if (this.isSendButtonDisabled) return;
        this.isLoading = true;
        try {
            const assetsArray = [];
            if (this.adaAmount && parseFloat(this.adaAmount) > 0) {
                assetsArray.push({ asset: 'ADA', amount: this.adaAmount });
            }
            this.tokens.forEach(token => {
                if (token.asset && token.amount && parseFloat(token.amount) > 0) {
                    assetsArray.push({ asset: token.asset, amount: token.amount });
                }
            });
            if (assetsArray.length > 1) {
                const outboundId = await createMultiAssetOutboundTransaction({
                    walletId: this.recordId,
                    toAddress: this.sendRecipient,
                    assets: assetsArray,
                    memo: this.sendMemo
                });
                showToast(this, 'Success', 'Multi-asset transaction created successfully!', 'success');
            } else if (assetsArray.length === 1) {
                const outboundId = await createOutboundTransaction({
                    walletId: this.recordId,
                    toAddress: this.sendRecipient,
                    amount: assetsArray[0].amount,
                    asset: assetsArray[0].asset,
                    memo: this.sendMemo
                });
                showToast(this, 'Success', 'Transaction created successfully!', 'success');
            } else {
                showToast(this, 'Error', 'No valid assets to send.', 'error');
                return;
            }
            this.showSend = false;
            this.fetchUtxoCounts();
        } catch (error) {
            showToast(this, 'Error', error.body?.message || error.message || 'Failed to create transaction', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    // Step Navigation Methods
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

    // Asset Methods
    initializeAssetOptions() {
        const options = [
            { label: 'ADA', value: 'ADA' }
        ];
        
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

    handleAssetChange(event) {
        this.selectedAsset = event.detail.value;
        this.updateSendState();
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
    
    getTokenOptions() {
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

    handleAdaAmountChange(event) {
        this.adaAmount = event.target.value;
        this.updateSendStateMultiAsset();
    }

    addToken() {
        const usedTickers = this.tokens.map(t => t.asset).filter(Boolean);
        const availableOptions = this.tokenOptions.filter(opt => !usedTickers.includes(opt.value));
        if (availableOptions.length === 0) {
            showToast(this, 'Info', 'All tokens already added.', 'info');
            return;
        }
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
    
    handleMemoChange(event) {
        this.sendMemo = event.target.value;
    }
    
    validateAddress() {
        const address = this.sendRecipient.trim();
        
        if (!address) {
            this.addressError = 'Recipient address is required';
            this.addressValid = false;
            return false;
        }
        
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
        
        const availableBalance = parseFloat(this.balance) || 0;
        if (amount > availableBalance) {
            this.amountError = `Insufficient balance. Available: ${availableBalance} ADA`;
            return false;
        }
        
        this.amountError = '';
        return true;
    }
    
    formatNumber(value, decimals = 2) {
        if (value === null || value === undefined || isNaN(value)) {
            return '0';
        }
        
        const numValue = parseFloat(value);
        
        if (decimals !== undefined && decimals !== null) {
            return numValue.toFixed(decimals);
        }
        
        if (numValue > 0 && numValue < 0.001) {
            return numValue.toFixed(6);
        }
        
        if (numValue < 1) {
            return numValue.toFixed(3);
        }
        
        if (numValue >= 1000000) {
            return (numValue / 1000000).toFixed(2) + 'M';
        } else if (numValue >= 1000) {
            return (numValue / 1000).toFixed(2) + 'K';
        } else {
            return numValue.toFixed(2);
        }
    }

    formatDate(dateString) {
        if (!dateString) return '';
        const date = new Date(dateString);
        return date.toLocaleString('en-US', {
            year: 'numeric', month: 'short', day: '2-digit',
            hour: '2-digit', minute: '2-digit', hour12: true
        });
    }
    
    async initializeWallet() {
        this.balance = '0';
        this.paymentAddress = 'Loading payment address...';
        this.isLoading = false;
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
}