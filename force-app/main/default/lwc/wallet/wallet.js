import { LightningElement, track, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { loadScript } from 'lightning/platformResourceLoader';
import qrcodeLibrary from '@salesforce/resourceUrl/qrcode';
import getUTXOAddresses from '@salesforce/apex/UTXOController.getUTXOAddresses';
import getUTXOAddressCountWithAssets from '@salesforce/apex/UTXOController.getUTXOAddressCountWithAssets';
import getAssetTokenSummary from '@salesforce/apex/UTXOController.getAssetTokenSummaryNoCache';
import getFirstUnusedReceivingAddress from '@salesforce/apex/UTXOController.getFirstUnusedReceivingAddress';
import { subscribe, MessageContext, APPLICATION_SCOPE } from 'lightning/messageService';
import WALLET_SYNC_CHANNEL from '@salesforce/messageChannel/WalletSyncChannel__c';
import cardanoLibrary from '@salesforce/resourceUrl/cardanoSerialization';
import getAllUtxoAssetsForWallet from '@salesforce/apex/UTXOController.getAllUtxoAssetsForWallet';
import createOutboundTransaction from '@salesforce/apex/UTXOController.createOutboundTransaction';
import updateOutboundTransactionStatus from '@salesforce/apex/UTXOController.updateOutboundTransactionStatus';
import updateOutboundTransactionDataAndStatus from '@salesforce/apex/UTXOController.updateOutboundTransactionDataAndStatus';

/* eslint-disable no-console */
const DEBUG = true;

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
    @track calculatedFee = '0.17'; // Placeholder, update with real fee logic
    @track totalAmount = '';
    @track errorMessage = '';
    @track isSendButtonDisabled = true;
    @track isMaxButtonDisabled = false;
    @track utxos = [];
    @track selectedUtxos = [];
    @track isCardanoLibLoaded = false;
    CardanoWasm = null;
    @track showReviewModal = false;
    @track pendingTransactionId = null;
    @track pendingTransactionData = null;

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
        if (DEBUG) console.log('[Wallet] fetchUtxoCounts start for', this.recordId);
        try {
            const data = await getUTXOAddresses({ walletId: this.recordId });
            const external = data.filter(addr => addr.Type__c === '0').length;
            const internal = data.filter(addr => addr.Type__c === '1').length;
            const summary = await getAssetTokenSummary({ walletId: this.recordId });
            if (DEBUG) console.log('[Wallet] Asset summary', summary);
            const tokens = summary.tokens || [];
            const tokenAmount = tokens.reduce((t, x)=>t + (x.amount || 0), 0);
            // Log counts for debugging; no toast shown
            // eslint-disable-next-line no-console
            console.log(`UTXO summary - Receiving: ${external}, Change: ${internal}, ADA: ${summary.ada}, Tokens: ${tokenAmount}`);
            this.balance = summary.ada ? summary.ada.toString() : '0';

            // Build assets list
            const assetRows = [];
            tokens.forEach(tok => {
                assetRows.push({
                    id: tok.symbol,
                    name: tok.symbol,
                    symbol: tok.symbol,
                    amount: tok.amount,
                    imgUrl: tok.icon || null,
                    icon: 'utility:apps'
                });
            });
            this.assets = assetRows;
            this.hasAssets = assetRows.length > 0;

            // Fetch payment address
            const payAddr = await getFirstUnusedReceivingAddress({ walletId: this.recordId });
            this.paymentAddress = payAddr ? payAddr : 'No unused address available';
            this.isAddressInvalid = !payAddr;
            if (DEBUG) console.log('[Wallet] fetchUtxoCounts done');
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
        if (DEBUG) console.log('[Send] openSendModal called');
        this.sendAmount = '';
        this.sendRecipient = '';
        this.calculatedFee = '0.17';
        this.totalAmount = '';
        this.errorMessage = '';
        this.isSendButtonDisabled = true;
        this.selectedUtxos = [];
        this.utxos = [];
        if (DEBUG) console.log('[Send] Modal state reset:', {
            sendAmount: this.sendAmount,
            sendRecipient: this.sendRecipient,
            calculatedFee: this.calculatedFee,
            totalAmount: this.totalAmount,
            errorMessage: this.errorMessage,
            isSendButtonDisabled: this.isSendButtonDisabled,
            selectedUtxosCount: this.selectedUtxos.length,
            utxosCount: this.utxos.length
        });
        
        if (DEBUG) console.log('[Send] Loading CardanoSerialization library...');
        this.loadCardanoLib();
        
        if (DEBUG) console.log('[Send] Fetching UTXOs for send...');
        this.fetchUtxosForSend();
        
        this.showSend = true;
        if (DEBUG) console.log('[Send] Modal opened successfully');
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

    connectedCallback() {
        // Subscribe to WalletSyncChannel messages
        this.subscription = subscribe(
            this.messageContext,
            WALLET_SYNC_CHANNEL,
            (msg) => {
                if (msg.walletId === this._recordId && msg.action === 'assetsUpdated') {
                    if (DEBUG) console.log('[Wallet] assetsUpdated message received, refreshing counts');
                    // Refresh balance information
                    this.fetchUtxoCounts();
                }
            },
            { scope: APPLICATION_SCOPE }
        );
    }

    disconnectedCallback() {
        if (this.subscription) {
            // no unsubscribe needed in most cases; stub left for completeness
            this.subscription = null;
        }
    }

    async loadCardanoLib() {
        if (DEBUG) console.log('[Send] loadCardanoLib called, isCardanoLibLoaded:', this.isCardanoLibLoaded);
        if (this.isCardanoLibLoaded) {
            if (DEBUG) console.log('[Send] CardanoSerialization already loaded, skipping');
            return;
        }
        try {
            if (DEBUG) console.log('[Send] Loading CardanoSerialization script...');
            await loadScript(this, `${cardanoLibrary}/cardanoSerialization/bundle.js`);
            if (DEBUG) console.log('[Send] Script loaded, setting CardanoWasm...');
            this.CardanoWasm = window.cardanoSerialization;
            this.isCardanoLibLoaded = true;
            if (DEBUG) console.log('[Send] CardanoSerialization loaded successfully:', {
                CardanoWasm: !!this.CardanoWasm,
                isCardanoLibLoaded: this.isCardanoLibLoaded
            });
        } catch (e) {
            this.errorMessage = 'Failed to load CardanoSerialization library.';
            if (DEBUG) console.error('[Send] CardanoSerialization load error:', {
                error: e,
                message: e.message,
                stack: e.stack
            });
        }
    }

    async fetchUtxosForSend() {
        if (DEBUG) console.log('[Send] fetchUtxosForSend started for wallet:', this.recordId);
        
        try {
            // Fetch all UTXO_Asset__c for this wallet
            if (DEBUG) console.log('[Send] Calling getAllUtxoAssetsForWallet Apex method...');
            const allAssets = await getAllUtxoAssetsForWallet({ walletId: this.recordId });
            if (DEBUG) console.log('[Send] Raw Apex response - allAssets:', JSON.stringify(allAssets, null, 2));
            if (DEBUG) console.log('[Send] Total assets returned:', allAssets ? allAssets.length : 0);
            
            // Group by UTXO_Address__c, filter for ADA (Blockfrost_ID__c == 'lovelace')
            if (DEBUG) console.log('[Send] Filtering for ADA (lovelace) assets...');
            const adaUtxos = allAssets.filter(a => {
                const isLovelace = a.Blockfrost_ID__c === 'lovelace';
                const hasAmount = a.Amount__c > 0;
                if (DEBUG) console.log(`[Send] Asset ${a.Id}: Blockfrost_ID__c=${a.Blockfrost_ID__c}, Amount__c=${a.Amount__c}, isLovelace=${isLovelace}, hasAmount=${hasAmount}`);
                return isLovelace && hasAmount;
            });
            if (DEBUG) console.log('[Send] Filtered ADA UTXOs (lovelace only):', JSON.stringify(adaUtxos, null, 2));
            if (DEBUG) console.log('[Send] ADA UTXOs count after filtering:', adaUtxos.length);
            
            // Map to structure needed for CardanoSerialization
            if (DEBUG) console.log('[Send] Mapping UTXOs to CardanoSerialization format...');
            this.utxos = adaUtxos.map((a, index) => {
                if (DEBUG) console.log(`[Send] Processing UTXO ${index + 1}/${adaUtxos.length}:`, {
                    id: a.Id,
                    utxoAddressId: a.UTXO_Address__c,
                    blockfrostId: a.Blockfrost_ID__c,
                    rawAmount: a.Amount__c,
                    rawAmountType: typeof a.Amount__c
                });
                
                const adaAmount = parseFloat(a.Amount__c);
                if (DEBUG) console.log(`[Send] Parsed ADA amount: ${adaAmount} (from ${a.Amount__c})`);
                
                const lovelaceAmount = Math.floor(adaAmount * 1000000); // Convert ADA to lovelace
                if (DEBUG) console.log(`[Send] Converted to lovelace: ${lovelaceAmount} (${adaAmount} * 1000000)`);
                
                if (DEBUG) console.log(`[Send] Processing UTXO ${a.Id}: ${adaAmount} ADA = ${lovelaceAmount} lovelace`);
                
                const mappedUtxo = {
                    utxoAssetId: a.Id,
                    utxoAddressId: a.UTXO_Address__c,
                    amount: adaAmount, // Keep ADA amount for display/calculation
                    lovelaceAmount: lovelaceAmount, // Add lovelace amount for CardanoSerialization
                    blockfrostId: a.Blockfrost_ID__c,
                    address: null, // will fill in later
                    lastTxHash: null, // will fill in later
                    lastTxIndex: null // will fill in later
                };
                
                if (DEBUG) console.log(`[Send] Mapped UTXO object ${index + 1}:`, JSON.stringify(mappedUtxo, null, 2));
                return mappedUtxo;
            });
            
            if (DEBUG) console.log('[Send] Final UTXOs array:', JSON.stringify(this.utxos, null, 2));
            if (DEBUG) console.log('[Send] Total ADA UTXOs found:', this.utxos.length);
            if (DEBUG) console.log('[Send] UTXOs array type:', typeof this.utxos);
            if (DEBUG) console.log('[Send] UTXOs is array:', Array.isArray(this.utxos));
            
            if (DEBUG) console.log('[Send] fetchUtxosForSend completed successfully');
        } catch (e) {
            this.errorMessage = 'Failed to fetch ADA UTXOs.';
            if (DEBUG) console.error('[Send] UTXO fetch error details:', {
                error: e,
                message: e.message,
                stack: e.stack,
                body: e.body,
                name: e.name
            });
        }
    }

    handleAmountChange(event) {
        if (DEBUG) console.log('[Send] handleAmountChange called with event:', event);
        const newAmount = event.target.value;
        if (DEBUG) console.log('[Send] New amount value:', newAmount, 'Type:', typeof newAmount);
        this.sendAmount = newAmount;
        if (DEBUG) console.log('[Send] Updated sendAmount:', this.sendAmount);
        this.updateSendState();
    }

    handleAddressChange(event) {
        if (DEBUG) console.log('[Send] handleAddressChange called with event:', event);
        const newAddress = event.target.value;
        if (DEBUG) console.log('[Send] New address value:', newAddress, 'Type:', typeof newAddress);
        this.sendRecipient = newAddress;
        if (DEBUG) console.log('[Send] Updated sendRecipient:', this.sendRecipient);
        this.updateSendState();
    }

    handleMaxAmount() {
        if (DEBUG) console.log('[Send] handleMaxAmount called');
        if (DEBUG) console.log('[Send] Current UTXOs for max calculation:', JSON.stringify(this.utxos, null, 2));
        
        // Set max ADA available (sum of all ADA UTXO assets minus fee)
        const totalAda = this.utxos.reduce((sum, u, index) => {
            const utxoAmount = parseFloat(u.amount);
            if (DEBUG) console.log(`[Send] UTXO ${index + 1}: ${utxoAmount} ADA, running sum: ${sum}`);
            return sum + utxoAmount;
        }, 0);
        
        if (DEBUG) console.log('[Send] Total ADA available:', totalAda);
        if (DEBUG) console.log('[Send] Current fee:', this.calculatedFee);
        
        const maxAmount = totalAda - parseFloat(this.calculatedFee);
        if (DEBUG) console.log('[Send] Max amount (total - fee):', maxAmount);
        
        this.sendAmount = maxAmount.toFixed(6);
        if (DEBUG) console.log('[Send] Set sendAmount to:', this.sendAmount);
        
        this.updateSendState();
    }

    updateSendState() {
        if (DEBUG) console.log('[Send] updateSendState called with:', JSON.stringify({
            sendAmount: this.sendAmount,
            sendRecipient: this.sendRecipient,
            calculatedFee: this.calculatedFee,
            utxosCount: this.utxos.length,
            utxos: this.utxos
        }, null, 2));
        
        // Validate input and select UTXOs
        if (DEBUG) console.log('[Send] Parsing amount and fee...');
        const amount = parseFloat(this.sendAmount);
        const fee = parseFloat(this.calculatedFee);
        
        if (DEBUG) console.log('[Send] Parsed values:', JSON.stringify({ 
            amount: amount, 
            fee: fee,
            amountType: typeof amount,
            feeType: typeof fee,
            isAmountValid: !isNaN(amount),
            isFeeValid: !isNaN(fee)
        }, null, 2));
        
        if (DEBUG) console.log('[Send] Validation check:', JSON.stringify({
            hasAmount: !!amount,
            amountPositive: amount > 0,
            hasRecipient: !!this.sendRecipient,
            amount: amount,
            recipient: this.sendRecipient,
            validationPassed: !(!amount || amount <= 0 || !this.sendRecipient)
        }, null, 2));
        
        if (!amount || amount <= 0 || !this.sendRecipient) {
            if (DEBUG) console.log('[Send] Validation failed:', JSON.stringify({
                hasAmount: !!amount,
                amountPositive: amount > 0,
                hasRecipient: !!this.sendRecipient,
                amount: amount,
                recipient: this.sendRecipient
            }, null, 2));
            this.isSendButtonDisabled = true;
            this.totalAmount = '';
            if (DEBUG) console.log('[Send] Send button disabled due to validation failure');
            return;
        }
        
        // Select UTXOs (greedy)
        if (DEBUG) console.log('[Send] Starting UTXO selection. Available UTXOs:', this.utxos.length);
        let sum = 0;
        let selected = [];
        const targetAmount = amount + fee;
        if (DEBUG) console.log('[Send] Target amount (amount + fee):', targetAmount);
        
        for (let i = 0; i < this.utxos.length; i++) {
            const utxo = this.utxos[i];
            if (DEBUG) console.log(`[Send] Considering UTXO ${i + 1}/${this.utxos.length}:`, JSON.stringify({
                utxoId: utxo.utxoAssetId,
                amount: utxo.amount,
                lovelaceAmount: utxo.lovelaceAmount
            }, null, 2));
            
            selected.push(utxo);
            const utxoAmount = parseFloat(utxo.amount);
            sum += utxoAmount;
            
            if (DEBUG) console.log(`[Send] Running sum: ${sum} ADA, target: ${targetAmount}`);
            if (sum >= targetAmount) {
                if (DEBUG) console.log('[Send] Target reached, stopping UTXO selection');
                break;
            }
        }
        
        this.selectedUtxos = selected;
        this.totalAmount = targetAmount.toFixed(6);
        
        if (DEBUG) console.log('[Send] UTXO selection results:', JSON.stringify({
            selectedCount: selected.length,
            totalSelected: sum,
            required: targetAmount,
            sufficient: sum >= targetAmount,
            selectedUtxos: selected
        }, null, 2));
        
        if (sum < targetAmount) {
            this.errorMessage = 'Insufficient ADA in UTXOs.';
            this.isSendButtonDisabled = true;
            if (DEBUG) console.log('[Send] Insufficient funds - disabling send button');
        } else {
            this.errorMessage = '';
            this.isSendButtonDisabled = false;
            if (DEBUG) console.log('[Send] Sufficient funds - enabling send button');
        }
        if (DEBUG) console.log('[Send] Selected ADA UTXOs:', JSON.stringify(this.selectedUtxos, null, 2));
        
        // Log the final state
        if (DEBUG) console.log('[Send] Final send state:', JSON.stringify({
            isSendButtonDisabled: this.isSendButtonDisabled,
            errorMessage: this.errorMessage,
            totalAmount: this.totalAmount,
            selectedUtxosCount: this.selectedUtxos.length
        }, null, 2));
    }

    async handleSend() {
        if (DEBUG) console.log('[Send] handleSend started');
        try {
            // Build all transaction data
            const txData = this.buildTransactionData();
            // Create Outbound_Transaction__c with all fields set
            const outboundTxId = await createOutboundTransaction({
                walletId: this.recordId,
                recipientAddress: txData.recipientAddress,
                amount: txData.amount,
                fee: txData.fee,
                changeAddress: txData.changeAddress,
                transactionData: txData.transactionData,
                inputs: txData.inputs,
                outputs: txData.outputs,
                metadata: txData.metadata,
                protocolParams: txData.protocolParams
            });
            this.showToast('Success', 'New Outbound Transaction Created', 'success');
            this.closeSendModal();
            if (DEBUG) console.log('[Send] Outbound Transaction created with ID:', outboundTxId);
        } catch (e) {
            this.errorMessage = 'Failed to create outbound transaction: ' + e.message;
            if (DEBUG) console.error('[Send] Error:', e);
        }
    }

    buildTransactionData() {
        // Build protocol parameters
        const protocolParams = {
            linearFee: {
                constant: '44',
                coefficient: '155381'
            },
            poolDeposit: '500000000',
            keyDeposit: '2000000',
            maxValueSize: 4000,
            maxTxSize: 8000,
            coinsPerUtxoByte: '34482'
        };
        // Build transaction inputs from selected UTXOs
        const inputs = this.selectedUtxos.map((utxo) => ({
            utxoAssetId: utxo.utxoAssetId,
            utxoAddressId: utxo.utxoAddressId,
            amount: utxo.amount.toString(),
            lovelaceAmount: utxo.lovelaceAmount.toString(),
            blockfrostId: utxo.blockfrostId,
            address: null,
            lastTxHash: null,
            lastTxIndex: null
        }));
        // Build transaction outputs
        const amount = parseFloat(this.sendAmount);
        const fee = parseFloat(this.calculatedFee);
        const totalInputAmount = this.selectedUtxos.reduce((sum, utxo) => sum + parseFloat(utxo.amount), 0);
        const changeAmount = totalInputAmount - amount - fee;
        const outputs = [
            {
                address: this.sendRecipient,
                amount: (amount * 1000000).toString(),
                type: 'payment',
                description: 'Payment to recipient'
            }
        ];
        if (changeAmount > 0) {
            outputs.push({
                address: this.paymentAddress,
                amount: (changeAmount * 1000000).toString(),
                type: 'change',
                description: 'Change back to sender'
            });
        }
        // Build transaction metadata
        const metadata = {
            ttl: 7200,
            validityStart: Math.floor(Date.now() / 1000),
            networkId: 1,
            totalInputAmount: totalInputAmount.toString(),
            totalOutputAmount: (amount + changeAmount).toString(),
            estimatedFee: fee.toString(),
            inputCount: inputs.length,
            outputCount: outputs.length
        };
        // Return all values needed for Apex
        return {
            protocolParams: JSON.stringify(protocolParams),
            inputs: JSON.stringify(inputs),
            outputs: JSON.stringify(outputs),
            metadata: JSON.stringify(metadata),
            transactionData: JSON.stringify({
                protocolParams,
                inputs,
                outputs,
                metadata,
                addresses: {
                    recipient: this.sendRecipient,
                    change: this.paymentAddress,
                    sender: this.paymentAddress
                },
                walletId: this.recordId,
                amount: amount.toString(),
                fee: fee.toString(),
                timestamp: new Date().toISOString()
            }),
            recipientAddress: this.sendRecipient,
            amount: amount.toString(),
            fee: fee.toString(),
            changeAddress: this.paymentAddress
        };
    }

    async handleReviewConfirm() {
        try {
            const txData = this.pendingTransactionData;
            await updateOutboundTransactionDataAndStatus({
                transactionId: this.pendingTransactionId,
                recipientAddress: txData.recipientAddress,
                amount: txData.amount,
                fee: txData.fee,
                changeAddress: txData.changeAddress,
                transactionData: txData.transactionData,
                inputs: txData.inputs,
                outputs: txData.outputs,
                metadata: txData.metadata,
                protocolParams: txData.protocolParams
            });
            this.showToast('Success', 'Transaction prepared and status set to Prepared.', 'success');
            this.showReviewModal = false;
            this.pendingTransactionId = null;
            this.pendingTransactionData = null;
            this.closeSendModal();
        } catch (e) {
            this.errorMessage = 'Failed to prepare transaction: ' + e.message;
            if (DEBUG) console.error('[Review] Error:', e);
        }
    }

    handleReviewCancel() {
        this.showReviewModal = false;
        this.pendingTransactionId = null;
        this.pendingTransactionData = null;
    }
}