import { LightningElement, track, api } from 'lwc';
import { loadScript } from 'lightning/platformResourceLoader';
import { subscribe, unsubscribe } from 'lightning/empApi';
import qrcodeLibrary from '@salesforce/resourceUrl/qrcode';
import getWalletAssetSummary from '@salesforce/apex/UTXOAssetController.getWalletAssetSummary';
import getFirstUnusedReceivingAddress from '@salesforce/apex/UTXOController.getFirstUnusedReceivingAddress';
import createOutboundTransaction from '@salesforce/apex/TransactionController.createOutboundTransaction';
import getAllUtxoAssetsForWallet from '@salesforce/apex/UTXOController.getAllUtxoAssetsForWallet';
import createMultiAssetOutboundTransaction from '@salesforce/apex/UTXOController.createMultiAssetOutboundTransaction';
import { showToast } from 'c/utils';
import { labels } from './labels';
import fetchWalletTransactions from '@salesforce/apex/UTXOAssetController.fetchWalletTransactions';
import getAllWalletAddresses from '@salesforce/apex/UTXOController.getAllWalletAddresses';
import syncAssetsAndTransactions from '@salesforce/apex/UTXOAssetController.syncAssetsAndTransactions';


export default class Wallet extends LightningElement {
    CHANNEL_NAME = '/event/WalletSyncEvent__e';

    _recordId;
    _inboundTransactions = [];
    _outboundTransactions = [];
    eventSubscription = null;

    @track balance = '0';
    @track paymentAddress = labels.UI.LOADING_PAYMENT_ADDRESS;
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
    @track selectedAsset = labels.UI.CURRENCY;
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
    @track tokenRowErrors = [];

    labels = labels;

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
        // Disable Next unless the address is valid
        return !this.addressValid;
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

    get memoCharCount() {
        return this.sendMemo ? this.sendMemo.length : 0;
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
        return Array.isArray(this.outboundTransactions) ? (this.showAllOutbound ? this.outboundTransactions : this.outboundTransactions.slice(0, 3)) : [];
    }

    get outboundTransactionsForDisplay() {
        return (this.visibleOutboundTransactions || []).map(tx => {
            const hash = tx.Transaction_Hash__c;
            let cardanoScanUrl = '';
            if (hash && typeof hash === 'string' && hash.length > 0) {
                cardanoScanUrl = `https://cardanoscan.io/transaction/${hash}`;
            }
            // Group lines by asset, summing amounts for duplicates
            let adaLine = null;
            let assetMap = {};
            if (Array.isArray(tx.lines)) {
                tx.lines.forEach(line => {
                    if (!line.Asset__c) return;
                    if (!assetMap[line.Asset__c]) {
                        assetMap[line.Asset__c] = { ...line };
                    } else {
                        // Sum the amounts for duplicate assets
                        assetMap[line.Asset__c].Amount__c =
                            (parseFloat(assetMap[line.Asset__c].Amount__c) || 0) + (parseFloat(line.Amount__c) || 0);
                    }
                });
            }
            // Build adaLine and otherAssetLines, ADA always first
            let otherAssetLines = [];
            Object.keys(assetMap).forEach(asset => {
                if (asset === 'ADA') {
                    adaLine = assetMap[asset];
                } else {
                    otherAssetLines.push(assetMap[asset]);
                }
            });
            // Sort otherAssetLines alphabetically by asset
            otherAssetLines.sort((a, b) => a.Asset__c.localeCompare(b.Asset__c));
            // Add recordUrl for navigation
            const recordUrl = tx.Id ? `/${tx.Id}` : '';
            return {
                ...tx,
                Transaction_Hash__c: hash,
                Transaction_Status__c: tx.Transaction_Status__c || '',
                cardanoScanUrl,
                adaLine,
                otherAssetLines,
                recordUrl
            };
        });
    }

    set inboundTransactions(value) {
        this._inboundTransactions = (value || []).map(tx => {
            const hash = tx.Transaction_Hash__c;
            let splitHash = hash;
            if (hash && typeof hash === 'string' && hash.length > 20) {
                const front = 24;
                const back = 24;
                splitHash = `${hash.slice(0, front)}...${hash.slice(-back)}`;
            }
            let cardanoScanUrl = '';
            if (hash && typeof hash === 'string' && hash.length > 0) {
                cardanoScanUrl = `https://cardanoscan.io/transaction/${hash}`;
            }
            // Add recordUrl for navigation
            const recordUrl = tx.Id ? `/${tx.Id}` : '';
            return {
                ...tx,
                splitHash,
                cardanoScanUrl,
                formattedDate: this.formatDate(tx.CreatedDate),
                recordUrl
            };
        });
    }

    get inboundTransactions() {
        return this._inboundTransactions || [];
    }

    set outboundTransactions(value) {
        this._outboundTransactions = (value || []).map(tx => {
            const hash = tx.Transaction_Hash__c;
            let cardanoScanUrl = '';
            if (hash && typeof hash === 'string' && hash.length > 0) {
                cardanoScanUrl = `https://cardanoscan.io/transaction/${hash}`;
            }
            return {
                ...tx,
                Transaction_Hash__c: hash,
                Transaction_Status__c: tx.Transaction_Status__c || '',
                cardanoScanUrl,
                formattedDate: this.formatDate(tx.CreatedDate)
            };
        });
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
            showToast(this, 'Error', labels.ERROR.FAILED_TO_LOAD_QR_CODE_LIBRARY, 'error');
        }
    }
    
    async fetchUtxoCounts() {
        try {
            const summary = await getWalletAssetSummary({ walletId: this.recordId });
            const allAssets = await getAllUtxoAssetsForWallet({ walletId: this.recordId });
            
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
                        amount: Number(token.amount), // always a number for validation
                        displayAmount: this.formatNumber(token.amount, assetDecimals), // for UI
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
        this.paymentAddress = payAddr ? payAddr : labels.UI.NO_UNUSED_ADDRESS_AVAILABLE;
            this.isAddressInvalid = !payAddr;
            // --- BEGIN: Sync all UTXO addresses for this wallet ---
            let utxoAddresses;
            try {
                utxoAddresses = await getAllWalletAddresses(this.recordId);
            } catch (e) {
                utxoAddresses = [];
            }
            if (Array.isArray(utxoAddresses)) {
                for (const addr of utxoAddresses) {
                    try {
                        await syncAssetsAndTransactions({ utxoAddressId: addr.Id });
                    } catch (e) {
                        // Optionally log error
                    }
                }
            }
            // --- END: Sync all UTXO addresses for this wallet ---
        } catch (error) {
            const message = error.body?.message || error.message || labels.ERROR.UNKNOWN_ERROR;
            showToast(this, 'Error', message, 'error');
        } finally {
            this.isLoading = false;
            await this.fetchWalletTransactions();
        }
    }

    async fetchWalletTransactions() {
        try {
            if (!this.recordId) {
                showToast(this, 'Error', 'No walletId provided for transaction query.', 'error');
                return;
            }
            const result = await fetchWalletTransactions({ walletId: this.recordId });
            if (result.success) {
                this.inboundTransactions = result.inbound || [];
                this.outboundTransactions = result.outbound || [];
            } else {
                this.inboundTransactions = [];
                this.outboundTransactions = [];
                showToast(this, 'Info', 'No transactions found for this wallet.', 'info');
            }
        } catch (error) {
            this.inboundTransactions = [];
            this.outboundTransactions = [];
            showToast(this, 'Error', error.body?.message || error.message || 'Unknown error fetching transactions', 'error');
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
            amount: Number(token.amount), // always a number for validation
            displayAmount: this.formatNumber(token.amount, token.decimals || 0), // for UI
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
    
    generateQrCode() {
        if (!this.isQrCodeLibraryLoaded || !this.paymentAddress || this.isAddressInvalid) {
            this.qrCodeError = true;
            showToast(this, 'Error', labels.ERROR.CANNOT_GENERATE_QR_CODE, 'error');
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
            showToast(this, 'Error', labels.ERROR.FAILED_TO_GENERATE_QR_CODE, 'error');
        }
    }
    
    openReceiveModal() {
        if (this.isAddressInvalid) {
            showToast(this, 'Error', labels.ERROR.CANNOT_OPEN_RECEIVE_MODAL, 'error');
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
        this.selectedAsset = labels.UI.CURRENCY;
        this.initializeAssetOptions();
        this.showSend = true;
    }

    closeSendModal() {
        this.showSend = false;
    }
    
    copyToClipboard() {
        if (navigator.clipboard && this.paymentAddress) {
            navigator.clipboard.writeText(this.paymentAddress).then(() => {
                showToast(this, 'Success', labels.SUCCESS.ADDRESS_COPIED_TO_CLIPBOARD, 'success');
            }).catch(() => {
                showToast(this, 'Error', labels.ERROR.FAILED_TO_COPY_ADDRESS_TO_CLIPBOARD, 'error');
            });
        } else {
            const textArea = document.createElement('textarea');
            textArea.value = this.paymentAddress;
            document.body.appendChild(textArea);
            textArea.select();
            try {
                document.execCommand('copy');
                showToast(this, 'Success', labels.SUCCESS.ADDRESS_COPIED_TO_CLIPBOARD, 'success');
            } catch (err) {
                showToast(this, 'Error', labels.ERROR.FAILED_TO_COPY_ADDRESS_TO_CLIPBOARD, 'error');
            }
            document.body.removeChild(textArea);
        }
    }

    shareLink() {
        showToast(this, 'Info', labels.INFO.QR_CODE_DOWNLOAD_NOT_IMPLEMENTED, 'info');
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
        this.validateAddress(); // Validate on every input
        this.validateSendForm();
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

    validateSendForm() {
        // Address must be valid
        if (!this.addressValid) {
            this.isSendButtonDisabled = true;
            return false;
        }

        // ADA validation (ADA is always required)
        const adaAvailable = parseFloat(this.balance);
        const adaAmountNum = parseFloat(this.adaAmount);
        const adaValid = !!this.adaAmount && !isNaN(adaAmountNum) && adaAmountNum > 0 && adaAmountNum <= adaAvailable;
        if (!adaValid) {
            this.isSendButtonDisabled = true;
            return false;
        }

        // Token validation (all added rows must be valid if any token row is present)
        let tokensValid = true;
        let tokenWarnings = [];
        let tokenRowErrors = [];
        if (this.tokens.length > 0) {
            tokensValid = this.tokens.every((token, idx) => {
                const asset = this.assets.find(a => a.symbol === token.asset);
                if (!token.asset || !token.amount) {
                    tokenWarnings.push({idx, reason: 'Missing asset or amount'});
                    tokenRowErrors[idx] = 'Select an asset and enter an amount.';
                    return false;
                }
                if (!asset) {
                    tokenWarnings.push({idx, reason: 'Asset not found'});
                    tokenRowErrors[idx] = 'Selected asset not found.';
                    return false;
                }
                const amount = parseFloat(token.amount);
                if (!(amount > 0 && amount <= asset.amount)) {
                    tokenWarnings.push({idx, reason: 'Amount invalid or exceeds available'});
                    tokenRowErrors[idx] = `Amount must be > 0 and ≤ ${asset.displayAmount}`;
                    return false;
                }
                tokenRowErrors[idx] = '';
                return true;
            });
        }
        this.tokenRowErrors = tokenRowErrors;
        this.isSendButtonDisabled = !(adaValid && tokensValid);
        return !this.isSendButtonDisabled;
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
                showToast(this, 'Success', labels.SUCCESS.MULTI_ASSET_TRANSACTION_CREATED_SUCCESSFULLY, 'success');
            } else if (assetsArray.length === 1) {
                const outboundId = await createOutboundTransaction({
                    walletId: this.recordId,
                    toAddress: this.sendRecipient,
                    amount: assetsArray[0].amount,
                    asset: assetsArray[0].asset,
                    memo: this.sendMemo
                });
                showToast(this, 'Success', labels.SUCCESS.TRANSACTION_CREATED_SUCCESSFULLY, 'success');
            } else {
                showToast(this, 'Error', labels.ERROR.NO_VALID_ASSETS_TO_SEND, 'error');
                return;
            }
            this.showSend = false;
            this.fetchUtxoCounts();
        } catch (error) {
            showToast(this, 'Error', error.body?.message || error.message || labels.ERROR.UNKNOWN_ERROR, 'error');
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
            { label: labels.UI.CURRENCY, value: labels.UI.CURRENCY }
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
    
    getTokenOptions(currentIndex = null) {
        // Exclude assets already selected in other token rows
        const usedAssets = this.tokens
            .map((t, i) => (currentIndex === null || i !== currentIndex) ? t.asset : null)
            .filter(Boolean);
        return this.assets
            .filter(asset => asset.symbol !== this.labels.UI.CURRENCY && !usedAssets.includes(asset.symbol))
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
        this.validateAdaAmount();
        this.validateSendForm();
    }

    validateAdaAmount() {
        const amount = parseFloat(this.adaAmount);
        const adaAvailable = parseFloat(this.balance);
        if (!this.adaAmount || isNaN(amount) || amount <= 0 || amount > adaAvailable) {
            this.amountError = 'Please enter a valid ADA amount.';
            return false;
        } else {
            this.amountError = '';
            return true;
        }
    }

    addToken() {
        const usedTickers = this.tokens.map(t => t.asset).filter(Boolean);
        const availableOptions = this.tokenOptions.filter(opt => !usedTickers.includes(opt.value));
        if (availableOptions.length === 0) {
            showToast(this, 'Info', labels.INFO.ALL_TOKENS_ALREADY_ADDED, 'info');
            return;
        }
        // Generate a unique id for each token row
        const uniqueId = `${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
        this.tokens = [
            ...this.tokens,
            { id: uniqueId, asset: '', amount: '', available: '', warning: '', placeholder: '', sendMaxDisabled: true }
        ];
        this.updateTokenComputedFields();
    }

    removeToken(event) {
        const index = parseInt(event.target.dataset.index, 10);
        this.tokens = this.tokens.filter((_, i) => i !== index);
        this.updateTokenComputedFields();
        this.validateSendForm();
    }

    handleTokenChange(event) {
        const index = parseInt(event.target.dataset.index, 10);
        const value = String(event.target.value); // Always use string
        this.tokens = this.tokens.map((token, i) =>
            i === index ? { ...token, asset: value, id: token.id } : token
        );
        this.updateTokenComputedFields();
    }

    handleTokenAmountChange(event) {
        const index = parseInt(event.target.dataset.index, 10);
        const value = event.target.value;
        this.tokens = this.tokens.map((token, i) =>
            i === index ? { ...token, amount: value } : token
        );
        this.updateTokenComputedFields();
    }

    updateTokenComputedFields() {
        this.tokens = this.tokens.map((token, idx, arr) => {
            let available = '';
            let warning = '';
            let placeholder = '';
            let sendMaxDisabled = !token.asset; // Disable Send Max if no asset selected
            // Compute options for this row: exclude assets already selected in other rows
            const usedAssets = arr.map((t, i) => (i !== idx ? t.asset : null)).filter(Boolean);
            const options = this.assets
                .filter(asset => asset.symbol !== this.labels.UI.CURRENCY && !usedAssets.includes(asset.symbol))
                .map(asset => ({
                    label: `${asset.symbol} (${asset.name})`,
                    value: asset.symbol
                }));
            if (token.asset) {
                const asset = this.assets.find(a => a.symbol === token.asset);
                if (asset) {
                    available = asset.displayAmount;
                    if (!token.amount) {
                        placeholder = available;
                    }
                    if (token.amount && parseFloat(token.amount) > parseFloat(asset.amount)) {
                        warning = `Exceeds available: ${available}`;
                    }
                } else {
                    warning = 'Asset not found';
                }
            } else if (token.amount) {
                warning = 'Select an asset';
            }
            if (!token.asset && !token.amount) warning = '';
            return { ...token, available, warning, placeholder, sendMaxDisabled, options };
        });
        // Also update tokenRowErrors for UI feedback
        this.validateSendForm();
    }

    handleSendMaxToken(event) {
        const index = parseInt(event.target.dataset.index, 10);
        const token = this.tokens[index];
        if (!token || !token.asset) return;
        const asset = this.assets.find(a => a.symbol === token.asset);
        if (!asset) return;
        let available;
        const decimals = asset.decimals !== undefined ? asset.decimals : 0;
        if (asset.rawAmount !== undefined && asset.rawAmount !== null) {
            available = parseFloat(asset.rawAmount) / Math.pow(10, decimals);
        } else {
            available = parseFloat(asset.amount);
        }
        this.tokens = this.tokens.map((t, i) =>
            i === index ? { ...t, amount: available.toFixed(decimals).toString() } : t
        );
        this.tokens = [...this.tokens]; // Force reactivity/UI update
        this.updateTokenComputedFields();
        this.validateSendForm();
    }



    handleAssetImgError(event) {
        const asset = this.assets.find(a => a.id === event.target.dataset.assetId);
        if (asset) {
            asset.showFallbackIcon = true;
        }
    }

    handleMemoChange(event) {
        this.sendMemo = event.target.value;
    }

    handleTransactionTabChange(event) {
        this.selectedTransactionType = event.target.value;
    }

    handleTransactionClick(event) {
        const recordId = event.currentTarget.dataset.id;
        if (recordId) {
            window.open('/' + recordId, '_blank');
        }
    }

    get outboundTransactionsWithUrl() {
        return (this.outboundTransactions || []).map(tx => ({
            ...tx,
            cardanoScanUrl: tx.Transaction_Hash__c ? `https://cardanoscan.io/transaction/${tx.Transaction_Hash__c}` : null
        }));
    }

    get visibleInboundTransactions() {
        return this.showAllInbound ? this.inboundTransactions : this.inboundTransactions.slice(0, 5);
    }

    get visibleOutboundTransactions() {
        return this.showAllOutbound ? this.outboundTransactions : this.outboundTransactions.slice(0, 5);
    }

    get inboundHasMore() {
        return this.inboundTransactions.length > 5;
    }

    get outboundHasMore() {
        return this.outboundTransactions.length > 5;
    }

    handleViewAllInbound() {
        this.showAllInbound = true;
    }

    handleViewAllOutbound() {
        this.showAllOutbound = true;
    }

    get computeRecordUrl() {
        return (id) => `/${id}`;
    }

    // Helper to format a number with specified decimals
    formatNumber(value, decimals = 6) {
        if (isNaN(value)) return '0';
        return parseFloat(value).toLocaleString(undefined, {
            minimumFractionDigits: decimals,
            maximumFractionDigits: decimals
        });
    }

    formatDate(dateString) {
        if (!dateString) return '';
        const date = new Date(dateString);
        if (isNaN(date.getTime())) return dateString;
        return date.toLocaleString(undefined, {
            year: 'numeric',
            month: 'short',
            day: '2-digit',
            hour: '2-digit',
            minute: '2-digit'
        });
    }

    get isAddTokenDisabled() {
        if (!this.tokens.length) return false;
        // All token rows must be valid
        const allRowsValid = this.tokens.every(token => {
            if (!token.asset || !token.amount) return false;
            const asset = this.assets.find(a => a.symbol === token.asset);
            if (!asset) return false;
            const amount = parseFloat(token.amount);
            if (!(amount > 0 && amount <= asset.amount)) return false;
            return true;
        });
        // Disable if all unique non-ADA assets are already added
        const nonAdaAssets = this.assets.filter(a => a.symbol !== this.labels.UI.CURRENCY);
        const usedAssets = this.tokens.map(t => t.asset).filter(Boolean);
        const unusedAssets = nonAdaAssets.filter(a => !usedAssets.includes(a.symbol));
        const allAssetsAdded = unusedAssets.length === 0;
        return !allRowsValid || allAssetsAdded;
    }
}