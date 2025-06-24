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
import checkIsAddressUsed from '@salesforce/apex/CreateNewWalletCtrl.checkIsAddressUsed';
import syncAssetsForWallet from '@salesforce/apex/UTXOController.syncAssetsForWallet';

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

    async generateAddress() {
        this.isLoading = true;
        try {
            if (!this.isLibraryLoaded) {
                throw new Error('Cardano libraries not loaded yet. Please wait and try again.');
            }

            const CardanoWasm = window.cardanoSerialization;

            // Determine the type based on the active tab
            const type = this.activeTab === 'external' ? '0' : '1'; // '0' for receiving (External), '1' for change (Internal)
            
            // Get the next index for the specified type
            const nextIndex = await getNextUTXOIndex({ walletId: this.recordId, type: type });

            // Fetch Wallet__c record to get the encrypted Account_Private_Key__c
            const wallet = await getWallet({ walletId: this.recordId });

            if (!wallet || !wallet.Account_Private_Key__c) {
                throw new Error('Wallet record or Account Private Key not found');
            }

            // Decrypt the Account_Private_Key__c
            const accountPrivateKeyBech32 = await decrypt({ encryptedText: wallet.Account_Private_Key__c });
            
            // Convert the Bech32 private key to a Bip32PrivateKey
            const accountPrivateKey = CardanoWasm.Bip32PrivateKey.from_bech32(accountPrivateKeyBech32);

            // Derive the new UTXO address for the next index
            const network = CardanoWasm.NetworkInfo.mainnet();
            const chainType = type === '0' ? 0 : 1; // 0 for external (receiving), 1 for internal (change)

            // Derive payment key (m/.../{chainType}/{nextIndex})
            const utxoPrivateKey = accountPrivateKey
                .derive(chainType) // External (0) or Internal (1) chain
                .derive(nextIndex); // Index
            const utxoPublicKey = utxoPrivateKey.to_public();
            const utxoKeyHash = utxoPublicKey.to_raw_key().hash();
            const utxoCred = CardanoWasm.Credential.from_keyhash(utxoKeyHash);

            // Derive stake key (m/.../2/{nextIndex})
            const stakePrivateKey = accountPrivateKey
                .derive(2) // Stake chain
                .derive(nextIndex) // Index
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

            // Save the new address to the database based on the type
            const newAddress = {
                index: nextIndex,
                publicKey: utxoPublicKey.to_bech32(),
                address: bech32Address,
                stakingKeyHash: stakeKeyHash.to_hex(),
                path: `m/1852'/1815'/${wallet.Account_Index__c}'/${chainType}/${nextIndex}`
            };

            if (type === '0') {
                await addReceivingUTXOAddress({
                    walletId: this.recordId,
                    receivingAddress: newAddress
                });
            } else {
                await addChangeUTXOAddress({
                    walletId: this.recordId,
                    changeAddress: newAddress
                });
            }

            // Sync assets for wallet to create UTXO_Asset__c rows for new address (if any UTXOs)
            try {
                await syncAssetsForWallet({ walletId: this.recordId });
                if (DEBUG) console.log('[GenerateAddress] Assets synced after new address');
            } catch (e) {
                if (DEBUG) console.error('[GenerateAddress] Asset sync failed', e);
            }

            // Refresh the UTXO addresses to update the counts and lists
            await refreshApex(this.wiredAddressesResult);

            // Broadcast message so other wallet-related components can refresh their data
            try {
                publish(this.messageContext, WALLET_SYNC_CHANNEL, {
                    walletId: this.recordId,
                    action: 'assetsUpdated'
                });
                if (DEBUG) console.log('[UTXO Refresh] WalletSyncChannel message published');
            } catch(e) {
                if (DEBUG) console.error('[UTXO Refresh] Failed to publish message', e);
            }

            // Show a toast notification with the new address
            this.showToast(
                'Success',
                `New ${type === '0' ? 'Receiving' : 'Change'} Address Derived`,
                'success'
            );
        } catch (error) {
            this.showToast('Error Generating Address', error.message || 'Unknown error', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({ title, message, variant })
        );
    }

    async handleRefreshAddressCounts() {
        this.isLoading = true;

        try {
            // Re-evaluate usage for existing addresses and then sync assets – no new derivations

            const evaluateChain = async (list, label) => {
                let consecutiveUnused = 0;
                for (let addr of list
                    .slice()
                    .sort((a, b) => (a.Index__c ?? 0) - (b.Index__c ?? 0))) {
                    const isUsed = await checkIsAddressUsed({ address: addr.Address__c });
                    if (DEBUG) console.log(`[UTXO Refresh] (${label}) ${addr.Address__c} used=${isUsed}`);
                    if (isUsed) {
                        break;
                    }
                    consecutiveUnused++;
                }
                if (DEBUG) console.log(`[UTXO Refresh] (${label}) consecutiveUnused=${consecutiveUnused}`);
            };

            await evaluateChain(this.externalAddresses, 'external');
            await evaluateChain(this.internalAddresses, 'internal');

            // Sync assets for ALL current addresses
            await syncAssetsForWallet({ walletId: this.recordId });
            if (DEBUG) console.log('[UTXO Refresh] Assets synced for wallet');

            await refreshApex(this.wiredAddressesResult);
            if (DEBUG) console.log('[UTXO Refresh] Apex data refreshed');

            // Broadcast update so wallet component refreshes balances
            try {
                publish(this.messageContext, WALLET_SYNC_CHANNEL, {
                    walletId: this.recordId,
                    action: 'assetsUpdated'
                });
                if (DEBUG) console.log('[UTXO Refresh] WalletSyncChannel message published');
            } catch(e) {
                if (DEBUG) console.error('[UTXO Refresh] Failed to publish message', e);
            }

            this.showToast('Success', 'UTXO assets refreshed for existing addresses.', 'success');
        } catch (err) {
            const msg = err.body?.message || err.message || 'Unknown error';
            if (DEBUG) console.error('[UTXO Refresh] Error', msg);
            this.showToast('Error', msg, 'error');
        } finally {
            this.isLoading = false;
        }
    }
}