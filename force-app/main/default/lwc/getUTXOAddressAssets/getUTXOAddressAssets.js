import { LightningElement, api, track, wire } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import WALLET_FIELD from '@salesforce/schema/UTXO_Address__c.Wallet__c';

import syncAssetsAndTransactions from '@salesforce/apex/UTXOAssetController.syncAssetsAndTransactions';
import setAddressesUsed from '@salesforce/apex/UTXOAssetController.setAddressesUsed';
import { isAddressActuallyUsed } from 'c/utils';

const LOVELACE_UNIT = 'lovelace';
const ADA_DIVISOR = 1000000;
const ADA_DECIMAL_PLACES = 6;

export default class GetUtxoAddressAssets extends LightningElement {
    @api recordId;
    @track isLoading = true;
    @track isSuccess = false;
    @track assets = [];
    @track error;

    @wire(getRecord, { recordId: '$recordId', fields: [WALLET_FIELD] })
    wiredRecord({ error, data }) {
        if (data) {
            this.syncAssets();
        } else if (error) {
            this.handleError(error);
        }
    }

    async syncAssets() {
        this.isLoading = true;
        this.error = undefined;
        
        try {
            const syncResult = await syncAssetsAndTransactions({ utxoAddressId: this.recordId });            
            
            if (syncResult?.success) {
                this.assets = this.flattenAssets(syncResult.assets || []);
                this.isSuccess = true;
                
                if (syncResult.statistics && isAddressActuallyUsed(syncResult.statistics)) {
                    await setAddressesUsed({ utxoAddressIds: [this.recordId] });
                }
            } else {
                this.error = syncResult?.message || 'Failed to fetch assets';
                this.isSuccess = false;
            }            
        } catch (error) {            
            this.handleError(error);
        } finally {
            this.isLoading = false;
            this.dispatchEvent(new CustomEvent('refreshevent'));
        }
    }

    flattenAssets(utxos) {
        const flattenedAssets = [];
        
        utxos.forEach(utxo => {
            const utxoData = {
                address: utxo.address,
                tx_hash: utxo.tx_hash,
                tx_index: utxo.tx_index,
                output_index: utxo.output_index,
                block: utxo.block
            };
            
            (utxo.amount || []).forEach(asset => {
                flattenedAssets.push({
                    ...utxoData,
                    unit: asset.unit,
                    quantity: asset.quantity,
                    uniqueKey: `${utxoData.tx_hash}_${utxoData.output_index}_${asset.unit}`,
                    formattedQuantity: this.formatQuantity(asset),
                    displayName: this.getDisplayName(asset),
                    formattedMetadata: this.formatMetadata(asset)
                });
            });
        });
        
        return flattenedAssets;
    }

    formatQuantity(asset) {
        if (asset.unit === LOVELACE_UNIT) {
            const adaAmount = (parseInt(asset.quantity || '0', 10) / ADA_DIVISOR).toFixed(ADA_DECIMAL_PLACES);
            return `${adaAmount} ADA`;
        }
        return asset.quantity;
    }

    getDisplayName(asset) {
        if (asset.unit === LOVELACE_UNIT) {
            return 'Cardano';
        }
        return asset.metadata?.name || asset.unit || 'Unknown Asset';
    }

    formatMetadata(asset) {
        try {
            return JSON.stringify(asset.metadata || {}, null, 2);
        } catch (e) {
            return 'Unable to display metadata';
        }
    }

    handleError(error) {
        this.error = error.body?.message || error.message || 'An error occurred';
        this.isSuccess = false;
        this.isLoading = false;
    }
}