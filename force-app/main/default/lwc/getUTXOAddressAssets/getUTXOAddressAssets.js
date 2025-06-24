import { LightningElement, api, track, wire } from 'lwc';
import syncADAAsset from '@salesforce/apex/UTXOController.syncADAAsset';
import getAddressExtended from '@salesforce/apex/UTXOController.getAddressExtended';
import { getRecord } from 'lightning/uiRecordApi';

const ADDRESS_FIELD = 'UTXO_Address__c.Address__c';

export default class GetUtxoAddressAssets extends LightningElement {
    /** Record Id of the UTXO_Address__c that launched the quick action */
    @api recordId;

    // UI constants
    labels = {
        TITLE: 'Get UTXO Address Assets',
        SPINNER_TEXT: 'Retrieving…',
        SUCCESS_TEXT: 'Assets retrieved successfully',
        SUCCESS_ICON_TEXT: 'Success',
        ERROR_TEXT: 'Failed to retrieve assets',
        ERROR_ICON_TEXT: 'Error'
    };

    icons = {
        SUCCESS: 'utility:success',
        ERROR: 'utility:error'
    };

    spinnerSize = {
        LARGE: 'large'
    };

    buttonVariants = {
        BRAND: 'brand'
    };

    @track isLoading = true;
    @track isSuccess = false;

    @wire(getRecord, { recordId: '$recordId', fields: [ADDRESS_FIELD] })
    wiredRecord({ error, data }) {
        if (data) {
            const address = data.fields.Address__c.value;
            this.callBlockfrost(address);
        } else if (error) {
            // eslint-disable-next-line no-console
            console.error('Error fetching address__c', error);
            this.isLoading = false;
        }
    }

    async callBlockfrost(address) {
        this.isLoading = true;
        // eslint-disable-next-line no-console
        console.log('Calling Blockfrost getAddressExtended for address', address);
        try {
            // Fetch full address extended details and log the raw JSON
            const extendedResponse = await getAddressExtended({ utxoAddressId: this.recordId });
            console.log('getAddressExtended response for', address, ':', extendedResponse);

            const adaAmount = await syncADAAsset({ utxoAddressId: this.recordId });
            console.log(`Synced ADA amount for address ${address}: ${adaAmount}`);
            this.isSuccess = true;
        } catch (err) {
            // eslint-disable-next-line no-console
            console.error('ADA sync error', err);
            this.isSuccess = false;
        } finally {
            this.isLoading = false;
        }
    }
}