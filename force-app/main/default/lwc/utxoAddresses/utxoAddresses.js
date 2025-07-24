import { LightningElement, api, wire, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { loadScript } from 'lightning/platformResourceLoader';
import { refreshApex } from '@salesforce/apex';

import UTXO_ADDRESS_OBJECT from '@salesforce/schema/UTXO_Address__c';
import IS_USED_FIELD from '@salesforce/schema/UTXO_Address__c.Is_Used__c';
import PATH_FIELD from '@salesforce/schema/UTXO_Address__c.Path__c';
import TYPE_FIELD from '@salesforce/schema/UTXO_Address__c.Type__c';
import ACCOUNT_PRIVATE_KEY_FIELD from '@salesforce/schema/Wallet__c.Account_Private_Key__c';
import ACCOUNT_INDEX_FIELD from '@salesforce/schema/Wallet__c.Account_Index__c';

import { isAddressActuallyUsed, truncateText, showToast, BIP32_PURPOSE, BIP32_COIN_TYPE, DERIVATION_PATHS, ADDRESS_TYPES } from 'c/utils';
import { labels } from './labels';

import cardanoLibrary from '@salesforce/resourceUrl/cardanoSerialization';

import decrypt from '@salesforce/apex/UTXOController.decrypt';
import getWallet from '@salesforce/apex/UTXOController.getWallet';
import getUTXOAddresses from '@salesforce/apex/UTXOController.getUTXOAddresses';
import getUserPermissions from '@salesforce/apex/UTXOController.getUserPermissions';
import getNextUTXOIndex from '@salesforce/apex/UTXOController.getNextUTXOIndex';
import addReceivingUTXOAddress from '@salesforce/apex/UTXOController.addReceivingUTXOAddress';
import addChangeUTXOAddress from '@salesforce/apex/UTXOController.addChangeUTXOAddress';
import syncAssetsAndTransactions from '@salesforce/apex/UTXOController.syncAssetsAndTransactions';
import setAddressesUsed from '@salesforce/apex/UTXOController.setAddressesUsed';

// UI constants
const DEFAULT_DISPLAY_LIMIT = 5;
const MAX_DISPLAY_LIMIT = 1000;
const TAB_TYPES = {
    EXTERNAL: 'external',
    INTERNAL: 'internal'
};


// URL constants
const CARDANOSCAN_URL_PREFIX = 'https://cardanoscan.io/address/';

// Action constants
const EDIT_ACTION = 'edit';
const IS_USED_LABEL = 'Is Used';

export default class UtxoAddresses extends NavigationMixin(LightningElement) {
    labels = labels;
    displayLimit = DEFAULT_DISPLAY_LIMIT;
    wiredAddressesResult; // To store the wired result for refresh
    viewLess = true;

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
    @track currentUnusedCount = 0;
    @track hasSeedPhrasePermission = false;
    @track filterText = '';
    @track isLibraryLoaded = false;

    // Datatable columns
    columns = [
        {
            label: labels.COLUMNS.NAME,
            fieldName: 'recordLink',
            type: 'url',
            typeAttributes: {
                label: { fieldName: 'Name' },
                target: '_self'
            },
            sortable: true,
            cellAttributes: { class: 'slds-text-link' }
        },
        { label: labels.COLUMNS.PATH, fieldName: this.getPathFieldName(), type: 'text' },
        {
            label: labels.COLUMNS.ADDRESS,
            fieldName: 'cardanoScanLink',
            type: 'url',
            typeAttributes: {
                label: { fieldName: 'truncatedAddress' },
                target: '_blank',
                tooltip: labels.COLUMNS.CARDANOSCAN_TOOLTIP
            },
            cellAttributes: { class: 'slds-text-link address-link' }
        },
        {
            label: IS_USED_LABEL,
            fieldName: this.getIsUsedFieldName(),
            type: 'boolean',
            cellAttributes: { alignment: 'center' }
        }
    ];
    
    get hasExternalAddresses() {
        return this.externalAddresses?.length > 0;
    }

    get hasInternalAddresses() {
        return this.internalAddresses?.length > 0;
    }

    get recordUrlPrefix() {
        return `/lightning/r/${this.getObjectApiName()}/`;
    }

    getObjectApiName() {
        return UTXO_ADDRESS_OBJECT.objectApiName;
    }

    getIsUsedFieldName() {
        return IS_USED_FIELD.fieldApiName;
    }

    getPathFieldName() {
        return PATH_FIELD.fieldApiName;
    }

    getTypeFieldName() {
        return TYPE_FIELD.fieldApiName;
    }    

    renderedCallback() {
        if (!this.isLibraryLoaded) {            
            this.loadLibraries();
        }
    }

    async loadLibraries() {
        try {
            await loadScript(this, `${cardanoLibrary}/cardanoSerialization/bundle.js`);
            
            if (!window.cardanoSerialization) {
                throw new Error(this.labels.ERROR.LIBRARY_INIT_ERROR);
            }
            this.isLibraryLoaded = true;
        } catch (error) {
            this.error = this.labels.ERROR.LIBRARY_LOAD_ERROR + ': ' + (error.message || error);
            showToast(this, this.labels.UI.ERROR_TITLE, this.error, 'error');
            setTimeout(() => this.loadLibraries(), 2000);
        }
    }

    @wire(getUserPermissions)
    wiredPermissions({ error, data }) {
        if (data) {
            this.hasSeedPhrasePermission = data.includes('Ada_Wallet_Seed_Phrase');
        } else if (error) {
            this.hasSeedPhrasePermission = false;
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
                recordLink: `${this.recordUrlPrefix}${addr.Id}/view`,
                cardanoScanLink: `${CARDANOSCAN_URL_PREFIX}${addr.Address__c}`,
                truncatedAddress: truncateText(addr.Address__c, 40, 20, 10)
            }));
            this.externalAddresses = addresses.filter(addr => addr[this.getTypeFieldName()] === ADDRESS_TYPES.RECEIVING);
            this.internalAddresses = addresses.filter(addr => addr[this.getTypeFieldName()] === ADDRESS_TYPES.CHANGE);
            this.displayedExternalAddresses = this.externalAddresses.slice(0, this.displayLimit);
            this.displayedInternalAddresses = this.internalAddresses.slice(0, this.displayLimit);
            this.updateTabState(this.activeTab);
            this.error = undefined;
        } else if (error) {
            this.error = error.body?.message || this.labels.ERROR.UNKNOWN_ERROR;
            this.externalAddresses = [];
            this.internalAddresses = [];
            this.displayedExternalAddresses = [];
            this.displayedInternalAddresses = [];
            this.currentTabCount = 0;
            this.currentUnusedCount = 0;
            showToast(this, this.labels.ERROR.LOAD_ERROR_TITLE, this.error, 'error');
        }
        this.isLoading = false;
    }

    handleExternalTabActive() {
        this.activeTab = TAB_TYPES.EXTERNAL;
        this.updateTabState(TAB_TYPES.EXTERNAL);
        this.applyFilter();
    }

    handleInternalTabActive() {
        this.activeTab = TAB_TYPES.INTERNAL;
        this.updateTabState(TAB_TYPES.INTERNAL);
        this.applyFilter();
    }

    updateTabState(tab) {
        if (tab === TAB_TYPES.EXTERNAL) {
            this.currentTabLabel = this.labels.UI.TAB_EXTERNAL;
            this.currentTabCount = this.externalAddresses.length;
            this.currentUnusedCount = this.externalAddresses.filter(addr => !addr[this.getIsUsedFieldName()]).length;
        } else if (tab === TAB_TYPES.INTERNAL) {
            this.currentTabLabel = this.labels.UI.TAB_INTERNAL;
            this.currentTabCount = this.internalAddresses.length;
            this.currentUnusedCount = this.internalAddresses.filter(addr => !addr[this.getIsUsedFieldName()]).length;
        }
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
                addr[this.getPathFieldName()].toLowerCase().includes(filter) ||
                addr.Address__c.toLowerCase().includes(filter)
            );
            filteredInternal = this.internalAddresses.filter(addr =>
                addr.Name.toLowerCase().includes(filter) ||
                addr[this.getPathFieldName()].toLowerCase().includes(filter) ||
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
        if (action.name === EDIT_ACTION) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: row.Id,
                    objectApiName: this.getObjectApiName(),
                    actionName: EDIT_ACTION
                }
            });
        }
    }

    handleViewAll() {
        this.displayLimit = MAX_DISPLAY_LIMIT;
        this.applyFilter();
        this.viewLess = false;
    }

    handleViewLess() {
        this.displayLimit = DEFAULT_DISPLAY_LIMIT;
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
                throw new Error(this.labels.ERROR.LIBRARY_NOT_LOADED);
            }

            const type = this.activeTab === TAB_TYPES.EXTERNAL ? ADDRESS_TYPES.RECEIVING : ADDRESS_TYPES.CHANGE;
            const typeLabel = type === ADDRESS_TYPES.RECEIVING ? 'receiving' : 'change';
            
            // Get the next index for the specified type
            const nextIndex = await getNextUTXOIndex({ walletId: this.recordId, type: type });

            // Fetch wallet data
            const wallet = await getWallet({ walletId: this.recordId });
            const accountPrivateKeyField = wallet[ACCOUNT_PRIVATE_KEY_FIELD.fieldApiName];
            if (!wallet || !accountPrivateKeyField) {
                throw new Error(this.labels.ERROR.WALLET_NOT_FOUND);
            }

            // Setup cryptographic components
            const accountPrivateKeyBech32 = await decrypt({ encryptedText: accountPrivateKeyField });
            const CardanoWasm = window.cardanoSerialization;
            const accountPrivateKey = CardanoWasm.Bip32PrivateKey.from_bech32(accountPrivateKeyBech32);
            const network = CardanoWasm.NetworkInfo.mainnet();
            const accountIndexNum = wallet[ACCOUNT_INDEX_FIELD.fieldApiName];
            const chainType = type === ADDRESS_TYPES.RECEIVING ? DERIVATION_PATHS.RECEIVING : DERIVATION_PATHS.CHANGE;

            // Derive payment key
            const utxoPrivateKey = accountPrivateKey
                .derive(chainType)
                .derive(nextIndex);
            const utxoPublicKey = utxoPrivateKey.to_public();
            const utxoKeyHash = utxoPublicKey.to_raw_key().hash();
            const utxoCred = CardanoWasm.Credential.from_keyhash(utxoKeyHash);

            // Derive stake key  
            const stakePrivateKey = accountPrivateKey
                .derive(DERIVATION_PATHS.STAKE)
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
                throw new Error(this.labels.ERROR.KEY_MISMATCH.replace('{typeLabel}', typeLabel).replace('{index}', nextIndex));
            }

            const fullPath = `m/${BIP32_PURPOSE}'/${BIP32_COIN_TYPE}'/${accountIndexNum}'/${chainType}/${nextIndex}`;

            // Create address data (using xpub/xpriv like create new wallet LWC)
            const newAddress = {
                index: nextIndex,
                publicKey: utxoPrivateKey.to_public().to_bech32(), // xpub
                privateKey: utxoPrivateKey.to_bech32(),            // xprv
                address: bech32Address,
                paymentKeyHash: utxoPublicKey.to_raw_key().hash().to_hex(), // Use payment key hash, not stake key hash
                path: fullPath
            };

            // Save to database
            let newAddressId;
            if (type === ADDRESS_TYPES.RECEIVING) {
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
            // Refresh data and notify other components
            await refreshApex(this.wiredAddressesResult);

            const successMessage = this.labels.SUCCESS.GENERATE_SUCCESS.replace('{typeLabel}', typeLabel.charAt(0).toUpperCase() + typeLabel.slice(1));
            showToast(this, successMessage, successMessage, 'success');

        } catch (error) {
            showToast(this, this.labels.UI.ERROR_TITLE, this.labels.ERROR.GENERATE_ERROR.replace('{error}', error.message), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleRefreshAddressCounts() {
        this.isLoading = true;

        try {
            if (!this.isLibraryLoaded) {
                throw new Error(this.labels.ERROR.LIBRARY_NOT_LOADED);
            }
            await this.syncExistingAddresses();

            // Refresh data
            await refreshApex(this.wiredAddressesResult);
            const message = this.labels.SUCCESS.REFRESH_SUCCESS;
                
            showToast(this, this.labels.SUCCESS.REFRESH_SUCCESS, message, 'success');

        } catch (err) {
            const msg = err.body?.message || err.message || this.labels.ERROR.UNKNOWN_ERROR;
            showToast(this, this.labels.UI.ERROR_TITLE, this.labels.ERROR.REFRESH_ERROR.replace('{error}', msg), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    /**
     * Sync assets and transactions for all existing UTXO addresses
     */
    async syncExistingAddresses() {
        const allAddresses = [...this.externalAddresses, ...this.internalAddresses];
        
        let syncedCount = 0;
        let errorCount = 0;
        
        for (const address of allAddresses) {
            try {
                const syncResult = await syncAssetsAndTransactions({ utxoAddressId: address.Id });
                
                if (syncResult.success) {
                    syncedCount++;
                } else {
                    errorCount++;
                }

                if (syncResult.success && syncResult.statistics) {
                    const stats = syncResult.statistics;
                    address.isUsed = isAddressActuallyUsed(stats);
                }
            } catch (syncError) {
                errorCount++;
            }
        }
        
        const usedAddressesIds = [];
        for (const address of allAddresses) {
            if (address.isUsed) {
                usedAddressesIds.push(address.Id);
            }
        }        

        await setAddressesUsed({ utxoAddressIds: usedAddressesIds });
        
        return { syncedCount, errorCount };
    }
}