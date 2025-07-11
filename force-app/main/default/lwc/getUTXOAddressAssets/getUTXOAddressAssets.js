import { LightningElement, api, track } from 'lwc';
import getAssetsAndTransactions from '@salesforce/apex/UTXOAssetController.syncAssetsAndTransactions';

export default class GetUTXOAddressAssets extends LightningElement {
    @api recordId;
    @track isLoading = false;
    @track showSuccess = false;
    @track showError = false;
    @track errorMessage = '';

    handleGetAssets() {
        this.isLoading = true;
        this.showSuccess = false;
        this.showError = false;
        this.errorMessage = '';
        getAssetsAndTransactions({ utxoAddressId: this.recordId })
            .then(result => {
                this.isLoading = false;
                if (result && result.success) {
                    this.showSuccess = true;
                } else {
                    this.showError = true;
                    this.errorMessage = result && result.message ? result.message : 'Failed to sync assets and transactions.';
                }
            })
            .catch(error => {
                this.isLoading = false;
                this.showSuccess = false;
                this.showError = true;
                this.errorMessage = error && error.body && error.body.message ? error.body.message : 'An error occurred while syncing.';
            });
    }
}