import { LightningElement, track, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { loadScript } from 'lightning/platformResourceLoader';
import qrcodeLibrary from '@salesforce/resourceUrl/qrcode';
import getUTXOAddresses from '@salesforce/apex/UTXOController.getUTXOAddresses';
import getWalletAssetSummary from '@salesforce/apex/UTXOAssetController.getWalletAssetSummary';
import getFirstUnusedReceivingAddress from '@salesforce/apex/UTXOController.getFirstUnusedReceivingAddress';
import getEpochParameters from '@salesforce/apex/BlockfrostService.getEpochParameters';
import { subscribe, unsubscribe, MessageContext, APPLICATION_SCOPE } from 'lightning/messageService';
import WALLET_SYNC_CHANNEL from '@salesforce/messageChannel/WalletSyncChannel__c';
import createMultiAssetOutboundTransaction from '@salesforce/apex/UTXOController.createMultiAssetOutboundTransaction';


export default class Wallet extends LightningElement {
    _recordId;
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
    @wire(MessageContext) messageContext;
    subscription = null;
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
    @track epochParameters = null;

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
            // Get UTXO address counts for debugging
            const data = await getUTXOAddresses({ walletId: this.recordId });
            const external = data.filter(addr => addr.Type__c === '0').length;
            const internal = data.filter(addr => addr.Type__c === '1').length;
            
            // Get asset summary using new method that properly handles ADA conversion
            const summary = await getWalletAssetSummary({ walletId: this.recordId });
            
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
                    
                    assetRows.push({
                        id: token.unit || token.symbol,
                        name: token.name || token.symbol,
                        symbol: token.symbol || token.unit,
                        amount: this.formatNumber(token.amount, assetDecimals), // Use actual asset decimals
                        rawAmount: token.rawAmount, // Keep raw amount for reference
                        decimals: token.decimals,
                        policyId: token.policyId,
                        fingerprint: token.fingerprint,
                        imgUrl: token.icon || null,
                        icon: 'utility:apps'
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

            // Fetch epoch parameters after wallet data is loaded
            await this.fetchEpochParameters();
        } catch (error) {
            const message = error.body?.message || error.message || 'Unknown error';
            this.showToast('Error', message, 'error');
        } finally {
            this.isLoading = false;
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
        this.subscribeToMessageChannel();
    }

    disconnectedCallback() {
        this.unsubscribeToMessageChannel();
    }

    subscribeToMessageChannel() {
        if (!this.subscription) {
            this.subscription = subscribe(
                this.messageContext,
                WALLET_SYNC_CHANNEL,
                (message) => this.handleMessage(message),
                { scope: APPLICATION_SCOPE }
            );
        }
    }

    unsubscribeToMessageChannel() {
        unsubscribe(this.subscription);
        this.subscription = null;
    }

    handleMessage(message) {
        if (message.recordId === this.recordId) {
            this.fetchUtxoCounts();
        }
    }

    handleAmountChange(event) {
        const newAmount = event.target.value;
        this.sendAmount = newAmount;
        this.updateSendState();
    }

    handleAddressChange(event) {
        const newAddress = event.target.value;
        this.sendRecipient = newAddress;
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
            // Gather all assets (ADA and tokens)
            const assets = [];
            if (this.adaAmount && parseFloat(this.adaAmount) > 0) {
                assets.push({ amount: this.adaAmount, asset: 'ADA' });
            }
            for (const token of this.tokens) {
                if (token.asset && token.amount && parseFloat(token.amount) > 0) {
                    assets.push({ amount: token.amount, asset: token.asset });
                }
            }
            console.log('[SEND] Prepared assets array:', JSON.stringify(assets));
            console.log('[SEND] Sending to Apex with walletId:', this.recordId, 'recipient:', this.sendRecipient);
            // Call new Apex method
            const outboundId = await createMultiAssetOutboundTransaction({
                walletId: this.recordId,
                toAddress: this.sendRecipient,
                assets
            });
            console.log('[SEND] Apex returned outboundId:', outboundId);
            this.showToast('Success', 'Transaction created successfully!', 'success');
            this.showSend = false;
            this.fetchUtxoCounts();
        } catch (error) {
            console.error('[SEND] Error from Apex:', error);
            this.showToast('Error', error.body?.message || error.message || 'Failed to create transaction', 'error');
        } finally {
            this.isLoading = false;
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

    async fetchEpochParameters() {
        try {
            console.log('[Wallet] Fetching epoch parameters...');
            const epochParamsJson = await getEpochParameters();
            
            // Parse the JSON response
            const epochParams = JSON.parse(epochParamsJson);
            
            // Store the epoch parameters
            this.epochParameters = epochParams;
            
            // Log the epoch parameters
            console.log('[Wallet] Epoch parameters loaded:', epochParams);
            console.log('[Wallet] Current epoch:', epochParams.epoch);
            console.log('[Wallet] Min fee A:', epochParams.min_fee_a);
            console.log('[Wallet] Min fee B:', epochParams.min_fee_b);
            console.log('[Wallet] Max tx size:', epochParams.max_tx_size);
            console.log('[Wallet] Max val size:', epochParams.max_val_size);
            console.log('[Wallet] Key deposit:', epochParams.key_deposit);
            console.log('[Wallet] Pool deposit:', epochParams.pool_deposit);
            console.log('[Wallet] Protocol major:', epochParams.protocol_major);
            console.log('[Wallet] Protocol minor:', epochParams.protocol_minor);
            
        } catch (error) {
            console.error('[Wallet] Error fetching epoch parameters:', error);
            this.showToast('Warning', 'Failed to fetch epoch parameters: ' + (error.body?.message || error.message), 'warning');
        }
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
}