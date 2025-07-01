import { LightningElement, api, track, wire } from 'lwc';
import syncAssetsAndTransactions from '@salesforce/apex/UTXOAssetController.syncAssetsAndTransactions';
import { getRecord } from 'lightning/uiRecordApi';

const WALLET_FIELD = 'UTXO_Address__c.Wallet__c';

export default class GetUtxoAddressAssets extends LightningElement {
    /** Record Id of the UTXO_Address__c that launched the quick action */
    @api recordId;
    @track walletId = '';
    @track error;

    @track isLoading = true;
    @track isSuccess = false;
    @track assets = [];
    @track error;

    @wire(getRecord, { recordId: '$recordId', fields: [WALLET_FIELD] })
    wiredRecord({ error, data }) {
        if (data) {
            this.walletId = data.fields.Wallet__c.value;
            this.syncAssets();
        } else if (error) {
            console.error('Error fetching wallet ID', error);
            this.isLoading = false;
            this.isSuccess = false;
        }
    }

    async syncAssets() {
        this.isLoading = true;
        this.error = undefined;
        
        try {
            console.log('[GetUTXOAddressAssets] Starting asset and transaction sync for address ID:', this.recordId);
            const syncResult = await syncAssetsAndTransactions({ utxoAddressId: this.recordId });
            console.log('[GetUTXOAddressAssets] syncAssetsAndTransactions response:', JSON.stringify(syncResult, null, 2));
            
            if (syncResult && syncResult.success) {
                // Flatten all individual assets from all UTXOs
                const flattenedAssets = [];
                
                (syncResult.assets || []).forEach(utxo => {
                    const utxoData = {
                        address: utxo.address,
                        tx_hash: utxo.tx_hash,
                        tx_index: utxo.tx_index,
                        output_index: utxo.output_index,
                        block: utxo.block
                    };
                    
                    // Process each individual asset within the UTXO
                    (utxo.amount || []).forEach(asset => {
                        flattenedAssets.push({
                            ...utxoData,
                            unit: asset.unit,
                            quantity: asset.quantity,
                            // Create a unique key using tx_hash, output_index, and unit
                            get uniqueKey() {
                                return `${utxoData.tx_hash}_${utxoData.output_index}_${asset.unit}`;
                            },
                            get formattedQuantity() {
                                if (asset.unit === 'lovelace') {
                                    return (parseInt(asset.quantity || '0', 10) / 1000000).toFixed(6) + ' ADA';
                                }
                                return asset.quantity;
                            },
                            get displayName() {
                                if (asset.unit === 'lovelace') {
                                    return 'Cardano';
                                }
                                return asset.metadata?.name || asset.unit || 'Unknown Asset';
                            },
                            get formattedMetadata() {
                                try {
                                    return JSON.stringify(asset.metadata || {}, null, 2);
                                } catch (e) {
                                    return 'Unable to display metadata';
                                }
                            }
                        });
                    });
                });
                
                this.assets = flattenedAssets;
                this.isSuccess = true;
                
                // Count assets by type for better logging
                const lovelaceAssets = flattenedAssets.filter(asset => asset.unit === 'lovelace');
                const nonLovelaceAssets = flattenedAssets.filter(asset => asset.unit !== 'lovelace');
                
                console.log('[GetUTXOAddressAssets] Successfully processed', flattenedAssets.length, 'assets');
                console.log('[GetUTXOAddressAssets] Asset breakdown:', {
                    totalAssets: flattenedAssets.length,
                    lovelaceAssets: lovelaceAssets.length, 
                    nonLovelaceAssets: nonLovelaceAssets.length,
                    uniqueUnits: [...new Set(flattenedAssets.map(asset => asset.unit))]
                });
            } else {
                this.error = syncResult?.message || 'Failed to fetch assets';
                this.isSuccess = false;
            }
        } catch (error) {
            console.error('[GetUTXOAddressAssets] Error syncing assets:', error);
            this.error = error.body?.message || error.message || 'An error occurred';
            this.isSuccess = false;
        } finally {
            this.isLoading = false;
            // Notify parent component that the sync is complete
            this.dispatchEvent(new CustomEvent('refreshevent'));
        }
    }
}