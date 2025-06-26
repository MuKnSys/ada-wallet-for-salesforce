import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import { loadScript } from 'lightning/platformResourceLoader';
import { refreshApex } from '@salesforce/apex';
import { publish, MessageContext } from 'lightning/messageService';

import cardanoLibrary from '@salesforce/resourceUrl/cardanoSerialization';
import bip39Library from '@salesforce/resourceUrl/bip39';

import getWallet from '@salesforce/apex/UTXOController.getWallet';
import decrypt from '@salesforce/apex/DataEncryptor.decrypt';

import getUTXOAddresses from '@salesforce/apex/UTXOController.getUTXOAddresses';
import getUserPermissions from '@salesforce/apex/UTXOController.getUserPermissions';
import getNextUTXOIndex from '@salesforce/apex/UTXOController.getNextUTXOIndex';
import addReceivingUTXOAddress from '@salesforce/apex/UTXOController.addReceivingUTXOAddress';
import addChangeUTXOAddress from '@salesforce/apex/UTXOController.addChangeUTXOAddress';
import checkAddressUsageOnly from '@salesforce/apex/CreateNewWalletCtrl.checkAddressUsageOnly';
import createUTXOAddressesBulk from '@salesforce/apex/CreateNewWalletCtrl.createUTXOAddressesBulk';
import syncAssetsAndTransactions from '@salesforce/apex/UTXOAssetController.syncAssetsAndTransactions';

import WALLET_SYNC_CHANNEL from '@salesforce/messageChannel/WalletSyncChannel__c';

/* eslint-disable no-console */
// Set DEBUG to true to enable console logging for refresh process
const DEBUG = true;

export default class UtxoAddresses extends NavigationMixin(LightningElement) {
    @api recordId;
    @track externalAddresses = [];
    @track internalAddresses = [];
    @track displayedExternalAddresses = [];
    @track displayedInternalAddresses = [];
    @track error;
    @track isLoading = false;
    @track activeTab = 'external';
    @track currentTabLabel = 'External';
    @track currentTabCount = 0;
    @track hasSeedPhrasePermission = false;
    @track dummyState = false; // For forcing re-render
    @track filterText = '';
    @track isLibraryLoaded = false;
    displayLimit = 5; // Limit to 5 addresses per tab
    wiredAddressesResult; // To store the wired result for refresh
    viewLess = true;
    @wire(MessageContext) messageContext;

    // Datatable columns
    columns = [
        {
            label: 'UTXO Address Name',
            fieldName: 'recordLink',
            type: 'url',
            typeAttributes: {
                label: { fieldName: 'Name' },
                target: '_self'
            },
            sortable: true,
            cellAttributes: { class: 'slds-text-link' }
        },
        { label: 'Path', fieldName: 'Path__c', type: 'text' },
        {
            label: 'Address',
            fieldName: 'cardanoScanLink',
            type: 'url',
            typeAttributes: {
                label: { fieldName: 'truncatedAddress' },
                target: '_blank',
                tooltip: 'Go to CardanoScan explorer'
            },
            cellAttributes: { class: 'slds-text-link address-link' }
        },
        {
            label: 'Staking Key Hash',
            fieldName: 'truncatedStakingKeyHash',
            type: 'text'
        }
    ];
    
    get hasExternalAddresses() {
        return this.externalAddresses?.length > 0;
    }

    get hasInternalAddresses() {
        return this.internalAddresses?.length > 0;
    }

    renderedCallback() {
        if (!this.isLibraryLoaded) {            
            this.loadLibraries();
        }
    }

    async loadLibraries() {
        const scripts = [
            { name: 'cardanoSerialization', url: `${cardanoLibrary}/cardanoSerialization/bundle.js` },
            { name: 'bip39', url: bip39Library }
        ];

        try {
            const loadResults = await Promise.all(
                scripts.map(async script => {
                    const result = await loadScript(this, script.url)
                        .then(() => {
                            return { name: script.name, loaded: true, url: script.url };
                        })
                        .catch(error => {
                            return { name: script.name, loaded: false, url: script.url, error };
                        });
                    return result;
                })
            );
            const failed = loadResults.filter(r => !r.loaded);
            if (failed.length) {
                throw new Error('Failed to load: ' + failed.map(f => f.name).join(', '));
            }
            if (!window.cardanoSerialization || !window.bip39) {
                throw new Error('Required libraries (cardanoSerialization or bip39) not properly initialized');
            }
            this.isLibraryLoaded = true;
        } catch (error) {
            this.error = 'Library loading failed: ' + (error.message || error);
            this.showToast('Error', this.error, 'error');
            setTimeout(() => this.loadLibraries(), 2000);
        }
    }

    @wire(getUserPermissions)
    wiredPermissions({ error, data }) {
        if (data) {
            this.hasSeedPhrasePermission = data.includes('Ada_Wallet_Seed_Phrase');
            this.dummyState = !this.dummyState;
        } else if (error) {
            this.hasSeedPhrasePermission = false;
            this.dummyState = !this.dummyState;
        }
    }

    @wire(getUTXOAddresses, { walletId: '$recordId' })
    wiredAddresses(result) {
        this.wiredAddressesResult = result;
        this.isLoading = true;
        const { error, data } = result;
        if (data) {
            const addresses = data.map(addr => ({
                ...addr,
                recordLink: `/lightning/r/UTXO_Address__c/${addr.Id}/view`,
                cardanoScanLink: `https://cardanoscan.io/address/${addr.Address__c}`,
                truncatedAddress: this.truncateText(addr.Address__c, 40, 20, 10),
                truncatedStakingKeyHash: this.truncateText(addr.Staking_Key_Hash__c, 40, 20, 10)
            }));
            this.externalAddresses = addresses.filter(addr => addr.Type__c === '0');
            this.internalAddresses = addresses.filter(addr => addr.Type__c === '1');
            this.displayedExternalAddresses = this.externalAddresses.slice(0, this.displayLimit);
            this.displayedInternalAddresses = this.internalAddresses.slice(0, this.displayLimit);
            this.updateTabState(this.activeTab);
            this.error = undefined;
        } else if (error) {
            this.error = error.body?.message || 'Unknown error';
            this.externalAddresses = [];
            this.internalAddresses = [];
            this.displayedExternalAddresses = [];
            this.displayedInternalAddresses = [];
            this.currentTabCount = 0;
            this.showToast('Error Loading Addresses', this.error, 'error');
        }
        this.isLoading = false;
    }

    truncateText(text, maxLength, firstChars, lastChars) {
        if (!text || text.length <= maxLength) {
            return text;
        }
        const firstPart = text.substring(0, firstChars);
        const lastPart = text.substring(text.length - lastChars);
        return `${firstPart}...${lastPart}`;
    }

    handleExternalTabActive() {
        this.activeTab = 'external';
        this.updateTabState('external');
        this.applyFilter();
    }

    handleInternalTabActive() {
        this.activeTab = 'internal';
        this.updateTabState('internal');
        this.applyFilter();
    }

    updateTabState(tab) {
        if (tab === 'external') {
            this.currentTabLabel = 'External';
            this.currentTabCount = this.externalAddresses.length; // Use full list for count
        } else if (tab === 'internal') {
            this.currentTabLabel = 'Internal';
            this.currentTabCount = this.internalAddresses.length; // Use full list for count
        }
        this.dummyState = !this.dummyState;
    }

    handleFilterChange(event) {
        this.filterText = event.target.value.toLowerCase();
        this.applyFilter();
    }

    applyFilter() {
        const filter = this.filterText.toLowerCase();
        let filteredExternal = this.externalAddresses;
        let filteredInternal = this.internalAddresses;

        if (filter) {
            filteredExternal = this.externalAddresses.filter(addr =>
                addr.Name.toLowerCase().includes(filter) ||
                addr.Path__c.toLowerCase().includes(filter) ||
                addr.Address__c.toLowerCase().includes(filter)
            );
            filteredInternal = this.internalAddresses.filter(addr =>
                addr.Name.toLowerCase().includes(filter) ||
                addr.Path__c.toLowerCase().includes(filter) ||
                addr.Address__c.toLowerCase().includes(filter)
            );
        }

        // Apply the display limit after filtering
        this.displayedExternalAddresses = filteredExternal.slice(0, this.displayLimit);
        this.displayedInternalAddresses = filteredInternal.slice(0, this.displayLimit);
        
        this.updateTabState(this.activeTab);
    }

    handleRowAction(event) {
        const action = event.detail.action;
        const row = event.detail.row;
        if (action.name === 'edit') {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: row.Id,
                    objectApiName: 'UTXO_Address__c',
                    actionName: 'edit'
                }
            });
        }
    }

    handleViewAll() {
        this.displayLimit = 1000;
        this.applyFilter();
        this.viewLess = false;
    }

    handleViewLess() {
        this.displayLimit = 5;
        this.applyFilter();
        this.viewLess = true;
    }

    // Helper to verify private key matches address payment key hash
    verifyKeyMatch(CardanoWasm, utxoPrivateKey, addressBech32) {
        const derivedPubKeyHash = utxoPrivateKey.to_public().to_raw_key().hash().to_hex();
        const addressObj = CardanoWasm.Address.from_bech32(addressBech32);
        const addressKeyHash =
            CardanoWasm.BaseAddress.from_address(addressObj)?.payment_cred().to_keyhash()?.to_hex() ||
            CardanoWasm.EnterpriseAddress.from_address(addressObj)?.payment_cred().to_keyhash()?.to_hex();
        return derivedPubKeyHash === addressKeyHash;
    }

    async generateAddress() {
        this.isLoading = true;
        try {
            if (!this.isLibraryLoaded) {
                throw new Error('Cardano libraries not loaded yet. Please wait and try again.');
            }

            const type = this.activeTab === 'external' ? '0' : '1'; // '0' for receiving, '1' for change
            const typeLabel = type === '0' ? 'receiving' : 'change';
            
            console.log(`[UTXOAddresses] 🔑 Generating single ${typeLabel} address for wallet: ${this.recordId}`);
            
            // Get the next index for the specified type
            const nextIndex = await getNextUTXOIndex({ walletId: this.recordId, type: type });
            console.log(`[UTXOAddresses] Next ${typeLabel} index: ${nextIndex}`);

            // Fetch wallet data
            const wallet = await getWallet({ walletId: this.recordId });
            if (!wallet || !wallet.Account_Private_Key__c) {
                throw new Error('Wallet record or Account Private Key not found');
            }

            // Setup cryptographic components
            const accountPrivateKeyBech32 = await decrypt({ encryptedText: wallet.Account_Private_Key__c });
            const CardanoWasm = window.cardanoSerialization;
            const accountPrivateKey = CardanoWasm.Bip32PrivateKey.from_bech32(accountPrivateKeyBech32);
            const network = CardanoWasm.NetworkInfo.mainnet();
            const accountIndexNum = wallet.Account_Index__c;
            const chainType = type === '0' ? 0 : 1; // 0 for external (receiving), 1 for internal (change)

            console.log(`[UTXOAddresses] 🔨 Deriving ${typeLabel} address #${nextIndex} for account ${accountIndexNum}`);

            // Derive payment key
            const utxoPrivateKey = accountPrivateKey
                .derive(chainType)
                .derive(nextIndex);
            const utxoPublicKey = utxoPrivateKey.to_public();
            const utxoKeyHash = utxoPublicKey.to_raw_key().hash();
            const utxoCred = CardanoWasm.Credential.from_keyhash(utxoKeyHash);

            // Derive stake key  
            const stakePrivateKey = accountPrivateKey
                .derive(2)
                .derive(0)
                .to_raw_key();
            const stakePublicKey = stakePrivateKey.to_public();
            const stakeKeyHash = stakePublicKey.hash();
            const stakeCred = CardanoWasm.Credential.from_keyhash(stakeKeyHash);

            // Create base address
            const baseAddress = CardanoWasm.BaseAddress.new(
                network.network_id(),
                utxoCred,
                stakeCred
            );
            const bech32Address = baseAddress.to_address().to_bech32();

            // Key verification
            const keyMatch = this.verifyKeyMatch(CardanoWasm, utxoPrivateKey, bech32Address);
            if (!keyMatch) {
                throw new Error(`Derived private key does not match address payment key hash for ${typeLabel} address #${nextIndex}`);
            }

            const fullPath = `m/1852'/1815'/${accountIndexNum}'/${chainType}/${nextIndex}`;

            // Create address data
            const newAddress = {
                index: nextIndex,
                publicKey: utxoPublicKey.to_bech32(),
                privateKey: utxoPrivateKey.to_bech32(),
                address: bech32Address,
                stakingKeyHash: stakeKeyHash.to_hex(),
                path: fullPath
            };

            console.log(`[UTXOAddresses] ✅ Derived ${typeLabel} address: ${bech32Address}`);

            // Save to database
            let newAddressId;
            if (type === '0') {
                newAddressId = await addReceivingUTXOAddress({
                    walletId: this.recordId,
                    receivingAddress: newAddress
                });
            } else {
                newAddressId = await addChangeUTXOAddress({
                    walletId: this.recordId,
                    changeAddress: newAddress
                });
            }
            
            console.log(`[UTXOAddresses] 💾 Saved ${typeLabel} address to database with ID: ${newAddressId}`);

            // Sync only the new address
            try {
                console.log(`[UTXOAddresses] 🔄 Syncing new ${typeLabel} address`);
                const syncResult = await syncAssetsAndTransactions({ utxoAddressId: newAddressId });
                
                if (syncResult.success) {
                    const stats = syncResult.statistics || {};
                    console.log(`[UTXOAddresses] ✅ Sync completed for new ${typeLabel} address:`, {
                        assetsInserted: stats.assetsInserted || 0,
                        assetsUpdated: stats.assetsUpdated || 0, 
                        transactionsInserted: stats.transactionsInserted || 0,
                        transactionsUpdated: stats.transactionsUpdated || 0
                    });
                } else {
                    console.warn(`[UTXOAddresses] ⚠️ Sync completed with warnings:`, syncResult.message);
                }
            } catch (e) {
                console.error(`[UTXOAddresses] ❌ Sync failed for new ${typeLabel} address:`, e);
                // Continue anyway - address was created successfully
            }

            // Refresh data and notify other components
            await refreshApex(this.wiredAddressesResult);
            
            try {
                publish(this.messageContext, WALLET_SYNC_CHANNEL, {
                    walletId: this.recordId,
                    action: 'assetsUpdated'
                });
            } catch(e) {
                console.error('[UTXOAddresses] Failed to publish wallet sync message:', e);
            }

            console.log(`[UTXOAddresses] 🎉 Successfully generated new ${typeLabel} address #${nextIndex}`);
            this.showToast('Success', `New ${typeLabel.charAt(0).toUpperCase() + typeLabel.slice(1)} Address Generated`, 'success');

        } catch (error) {
            console.error('[UTXOAddresses] ❌ Error generating address:', error);
            this.showToast('Error', `Failed to generate address: ${error.message}`, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({ title, message, variant })
        );
    }

    // Helper for refresh: verify and update UTXO keys
    async verifyAndUpdateUTXOKeys(addressList, CardanoWasm, accountPrivateKey) {
        for (const addr of addressList) {
            // Parse path: m/1852'/1815'/0'/0/0
            const pathParts = addr.Path__c.split('/');
            const chainType = parseInt(pathParts[4]);
            const index = parseInt(pathParts[5]);
            console.log(`[UTXOAddresses] Verifying UTXO for path: ${addr.Path__c}`);
            console.log(`[UTXOAddresses] Account private key (bech32): ${accountPrivateKey.to_bech32()}`);
            const utxoPrivateKey = accountPrivateKey.derive(chainType).derive(index);
            console.log(`[UTXOAddresses] Derived UTXO private key (bech32): ${utxoPrivateKey.to_bech32()}`);
            const utxoPublicKey = utxoPrivateKey.to_public();
            console.log(`[UTXOAddresses] Derived UTXO public key (bech32): ${utxoPublicKey.to_bech32()}`);
            const utxoKeyHash = utxoPublicKey.to_raw_key().hash();
            console.log(`[UTXOAddresses] Derived UTXO key hash: ${utxoKeyHash.to_hex()}`);
            const keyMatch = this.verifyKeyMatch(CardanoWasm, utxoPrivateKey, addr.Address__c);
            if (keyMatch) {
                console.log(`[UTXOAddresses] Key verification PASSED for path: ${addr.Path__c}`);
                // TODO: Call Apex to update Private_Key__c if needed
            } else {
                console.error(`[UTXOAddresses] ERROR: Key mismatch for address ${addr.Address__c} at path: ${addr.Path__c}`);
            }
        }
    }

    async handleRefreshAddressCounts() {
        this.isLoading = true;

        console.log(`[UTXOAddresses] 🚀 Starting comprehensive UTXO refresh for wallet: ${this.recordId}`);
        console.log(`[UTXOAddresses] Current addresses - External: ${this.externalAddresses.length}, Internal: ${this.internalAddresses.length}`);

        try {
            if (!this.isLibraryLoaded) {
                throw new Error('Cardano libraries not loaded yet. Please wait and try again.');
            }

            // Fetch wallet and setup crypto
            const wallet = await getWallet({ walletId: this.recordId });
            if (!wallet || !wallet.Account_Private_Key__c) {
                throw new Error('Wallet record or Account Private Key not found');
            }

            const accountPrivateKeyBech32 = await decrypt({ encryptedText: wallet.Account_Private_Key__c });
            const CardanoWasm = window.cardanoSerialization;
            const accountPrivateKey = CardanoWasm.Bip32PrivateKey.from_bech32(accountPrivateKeyBech32);
            const network = CardanoWasm.NetworkInfo.mainnet();
            const accountIndexNum = wallet.Account_Index__c;
            
            // Derive stake key for new addresses
            const stakePrivateKey = accountPrivateKey.derive(2).derive(0).to_raw_key();
            const stakePublicKey = stakePrivateKey.to_public();
            const stakeKeyHash = stakePublicKey.hash();
            const stakeCred = CardanoWasm.Credential.from_keyhash(stakeKeyHash);

            // Phase 1: Sync existing addresses
            console.log(`[UTXOAddresses] 📊 Phase 1: Syncing existing addresses`);
            await this.syncExistingAddresses();

            // Phase 2: Ensure 20 consecutive unused addresses for both receiving and change
            console.log(`[UTXOAddresses] 🔍 Phase 2: Ensuring 20 consecutive unused addresses`);
            
            const receivingAddressesToAdd = await this.ensureConsecutiveUnusedAddresses(
                this.externalAddresses, 0, accountPrivateKey, stakeCred, network, accountIndexNum, 'receiving'
            );
            
            const changeAddressesToAdd = await this.ensureConsecutiveUnusedAddresses(
                this.internalAddresses, 1, accountPrivateKey, stakeCred, network, accountIndexNum, 'change'
            );

            // Phase 3: Create new addresses if needed
            if (receivingAddressesToAdd.length > 0 || changeAddressesToAdd.length > 0) {
                console.log(`[UTXOAddresses] 💾 Phase 3: Creating ${receivingAddressesToAdd.length} receiving and ${changeAddressesToAdd.length} change addresses`);
                
                const createResult = await createUTXOAddressesBulk({
                    walletId: this.recordId,
                    receivingAddresses: receivingAddressesToAdd,
                    changeAddresses: changeAddressesToAdd
                });

                console.log(`[UTXOAddresses] ✅ Created new addresses:`, createResult);

                // Phase 4: Sync new addresses
                console.log(`[UTXOAddresses] 🔄 Phase 4: Syncing new addresses`);
                const allNewAddresses = [...(createResult.receivingAddresses || []), ...(createResult.changeAddresses || [])];
                
                for (const newAddr of allNewAddresses) {
                    if (newAddr.utxoAddressId) {
                        try {
                            const syncResult = await syncAssetsAndTransactions({ utxoAddressId: newAddr.utxoAddressId });
                            console.log(`[UTXOAddresses] ✅ Synced new address ${newAddr.address}:`, syncResult);
                        } catch (syncError) {
                            console.error(`[UTXOAddresses] ❌ Failed to sync new address ${newAddr.address}:`, syncError);
                        }
                    }
                }
            } else {
                console.log(`[UTXOAddresses] ✅ No new addresses needed - already have 20 consecutive unused`);
            }

            // Refresh data and notify other components
            await refreshApex(this.wiredAddressesResult);
            console.log(`[UTXOAddresses] 🔄 Refreshed address data`);

            // Broadcast update so wallet component refreshes balances
            try {
                publish(this.messageContext, WALLET_SYNC_CHANNEL, {
                    walletId: this.recordId,
                    action: 'assetsUpdated'
                });
                console.log(`[UTXOAddresses] 📢 Published wallet sync message`);
            } catch(e) {
                console.error('[UTXOAddresses] Failed to publish message:', e);
            }

            const totalNew = (receivingAddressesToAdd?.length || 0) + (changeAddressesToAdd?.length || 0);
            const message = totalNew > 0 
                ? `UTXO refresh completed. Created ${totalNew} new addresses and synced all assets.`
                : 'UTXO refresh completed. All assets synced for existing addresses.';
                
            console.log(`[UTXOAddresses] 🎉 Refresh completed successfully`);
            this.showToast('Success', message, 'success');

        } catch (err) {
            const msg = err.body?.message || err.message || 'Unknown error';
            console.error('[UTXOAddresses] ❌ Error during UTXO refresh:', msg);
            this.showToast('Error', `UTXO refresh failed: ${msg}`, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    /**
     * Sync assets and transactions for all existing UTXO addresses
     */
    async syncExistingAddresses() {
        const allAddresses = [...this.externalAddresses, ...this.internalAddresses];
        console.log(`[UTXOAddresses] Syncing ${allAddresses.length} existing addresses`);
        
        let syncedCount = 0;
        let errorCount = 0;
        
        for (const address of allAddresses) {
            try {
                console.log(`[UTXOAddresses] 🔄 Syncing address: ${address.Address__c} (${address.Type__c === '0' ? 'receiving' : 'change'})`);
                
                const syncResult = await syncAssetsAndTransactions({ utxoAddressId: address.Id });
                
                if (syncResult.success) {
                    syncedCount++;
                    console.log(`[UTXOAddresses] ✅ Successfully synced ${address.Address__c}`);
                } else {
                    errorCount++;
                    console.error(`[UTXOAddresses] ❌ Failed to sync ${address.Address__c}:`, syncResult.message);
                }
            } catch (syncError) {
                errorCount++;
                console.error(`[UTXOAddresses] ❌ Error syncing ${address.Address__c}:`, syncError);
            }
        }
        
        console.log(`[UTXOAddresses] 📊 Sync summary - Synced: ${syncedCount}, Failed: ${errorCount}`);
        return { syncedCount, errorCount };
    }

    /**
     * Ensure 20 consecutive unused addresses exist, derive new ones if needed
     */
    async ensureConsecutiveUnusedAddresses(existingAddresses, derivationPath, accountPrivateKey, stakeCred, network, accountIndexNum, typeLabel) {
        const targetConsecutive = 20;
        console.log(`[UTXOAddresses] 🎯 Ensuring ${targetConsecutive} consecutive unused ${typeLabel} addresses`);
        
        // Sort existing addresses by index
        const sortedAddresses = existingAddresses
            .slice()
            .sort((a, b) => (a.Index__c ?? 0) - (b.Index__c ?? 0));
        
        console.log(`[UTXOAddresses] Current ${typeLabel} addresses: ${sortedAddresses.length}`);
        
        // Find current consecutive unused count from the end
        let consecutiveUnused = 0;
        let lastUsedIndex = -1;
        
        // Check existing addresses from highest index down to find consecutive unused
        for (let i = sortedAddresses.length - 1; i >= 0; i--) {
            const address = sortedAddresses[i];
            console.log(`[UTXOAddresses] Checking ${typeLabel} address #${address.Index__c}: ${address.Address__c}`);
            
            try {
                const usageResult = await checkAddressUsageOnly({ address: address.Address__c });
                const isUsed = usageResult.isUsed || false;
                
                console.log(`[UTXOAddresses] ${typeLabel} address #${address.Index__c} is ${isUsed ? 'USED' : 'UNUSED'}`);
                
                if (isUsed) {
                    lastUsedIndex = address.Index__c;
                    break; // Stop when we find a used address
                } else {
                    consecutiveUnused++;
                }
            } catch (error) {
                console.error(`[UTXOAddresses] ❌ Error checking ${typeLabel} address #${address.Index__c}:`, error);
                // Assume unused if check fails
                consecutiveUnused++;
            }
        }
        
        console.log(`[UTXOAddresses] 📊 ${typeLabel} analysis - Consecutive unused: ${consecutiveUnused}, Last used index: ${lastUsedIndex}`);
        
        // If we already have enough consecutive unused, return empty array
        if (consecutiveUnused >= targetConsecutive) {
            console.log(`[UTXOAddresses] ✅ Already have ${consecutiveUnused} consecutive unused ${typeLabel} addresses`);
            return [];
        }
        
        // Calculate how many more we need and starting index
        const neededCount = targetConsecutive - consecutiveUnused;
        const nextIndex = sortedAddresses.length > 0 ? 
            Math.max(...sortedAddresses.map(a => a.Index__c ?? 0)) + 1 : 0;
        
        console.log(`[UTXOAddresses] 🔨 Need to derive ${neededCount} more ${typeLabel} addresses starting from index ${nextIndex}`);
        
        // Derive new addresses
        const newAddresses = [];
        const CardanoWasm = window.cardanoSerialization;
        
        for (let i = 0; i < neededCount; i++) {
            const currentIndex = nextIndex + i;
            
            try {
                console.log(`[UTXOAddresses] 🔑 Deriving ${typeLabel} address #${currentIndex}`);
                
                // Derive payment key
                const utxoPrivateKey = accountPrivateKey
                    .derive(derivationPath)
                    .derive(currentIndex);
                const utxoPublicKey = utxoPrivateKey.to_public();
                const utxoKeyHash = utxoPublicKey.to_raw_key().hash();
                const utxoCred = CardanoWasm.Credential.from_keyhash(utxoKeyHash);

                // Create base address
                const baseAddress = CardanoWasm.BaseAddress.new(
                    network.network_id(),
                    utxoCred,
                    stakeCred
                );
                const bech32Address = baseAddress.to_address().to_bech32();

                // Key verification
                const keyMatch = this.verifyKeyMatch(CardanoWasm, utxoPrivateKey, bech32Address);
                if (!keyMatch) {
                    throw new Error(`Derived private key does not match address payment key hash for ${typeLabel} address #${currentIndex}`);
                }

                const fullPath = `m/1852'/1815'/${accountIndexNum}'/${derivationPath}/${currentIndex}`;
                
                const addressData = {
                    index: currentIndex,
                    publicKey: utxoPublicKey.to_bech32(),
                    privateKey: utxoPrivateKey.to_bech32(),
                    address: bech32Address,
                    stakingKeyHash: stakeCred.to_keyhash().to_hex(),
                    path: fullPath
                };
                
                newAddresses.push(addressData);
                console.log(`[UTXOAddresses] ✅ Derived ${typeLabel} address #${currentIndex}: ${bech32Address}`);
                
            } catch (error) {
                console.error(`[UTXOAddresses] ❌ Failed to derive ${typeLabel} address #${currentIndex}:`, error);
                throw error;
            }
        }
        
        console.log(`[UTXOAddresses] 🎉 Derived ${newAddresses.length} new ${typeLabel} addresses`);
        return newAddresses;
    }
}