import { LightningElement, api, track } from 'lwc';
import { isAddressActuallyUsed, showToast } from 'c/utils';

import { labels } from './labels';

import syncAssetsAndTransactions from '@salesforce/apex/UTXOAssetController.syncAssetsAndTransactions';
import setAddressesUsed from '@salesforce/apex/UTXOAssetController.setAddressesUsed';

const LOVELACE_UNIT = 'lovelace';
const ADA_DIVISOR = 1000000;
const ADA_DECIMAL_PLACES = 6;

export default class GetUtxoAddressAssets extends LightningElement {
    @api recordId;
    @track isLoading = false;
    @track assets = [];
    @track error;

    labels = labels;

    async handleSyncAssets() {
        this.isLoading = true;
        this.error = undefined;
        
        try {
            const syncResult = await syncAssetsAndTransactions({ utxoAddressId: this.recordId });            
            
            if (syncResult?.success) {
                this.assets = this.flattenAssets(syncResult.assets || []);
                
                if (syncResult.statistics && isAddressActuallyUsed(syncResult.statistics)) {
                    await setAddressesUsed({ utxoAddressIds: [this.recordId] });
                }
                
                showToast(this, 'Success', this.labels.SYNC.SuccessMessage, 'success');
            } else {
                this.error = syncResult?.message || this.labels.ERROR.Default;
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
                    displayName: this.getDisplayName(asset)
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

    handleError(error) {
        this.error = error.body?.message || error.message || this.labels.ERROR.Unknown;
        this.isLoading = false;
    }
}