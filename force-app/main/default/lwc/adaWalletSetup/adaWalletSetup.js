import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import { labels } from './labels';
import { TOAST_VARIANT, TOAST_MODE, STEPS } from 'c/constants';

import getSetup from '@salesforce/apex/AdaWalletsSetupCtrl.getSetup';
import generatePrivateKey from '@salesforce/apex/AdaWalletsSetupCtrl.generatePrivateKey';
import enableLogging from '@salesforce/apex/AdaWalletsSetupCtrl.enableLogging';
import disableLogging from '@salesforce/apex/AdaWalletsSetupCtrl.disableLogging';
import saveBlockfrostProjectId from '@salesforce/apex/AdaWalletsSetupCtrl.saveBlockfrostProjectId';
import testBlockfrostConfig from '@salesforce/apex/BlockfrostConnector.testBlockfrostConfig';

export default class AdaWalletSetup extends LightningElement {
    isLoading = true;
    labels = labels;
    steps = STEPS;
    dataChanged = false;

    @track
    setupData = {};
    @track 
    blockfrostProjectId = '';
    @track 
    testResult = '';
    @track 
    isProjectIdSet = false;    

    get privateKeyCompleted() {
        return !this.isBlank(this.setupData, 'privateKey');
    }

    get isSaveDisabled() {
        return !this.dataChanged || !this.blockfrostProjectId;
    }

    get isRemoveDisabled() {
        return !this.isProjectIdSet;
    }

    get isTestDisabled() {
        return !this.isProjectIdSet;
    }

    get isProjectIdNotSet() {
        return !this.isProjectIdSet;
    }

    isBlank(object, value) {
        return !(value in object && object[value] !== undefined && object[value] !== null && object[value] !== '');
    }

    processSetupData(value) {
        Object.assign(this.setupData, value);
    }

    handleBlockfrostIdChange(event) {
        this.blockfrostProjectId = event.target.value;
        this.dataChanged = true;
    }

    async loadSetup() {
        this.isLoading = true;
        try {
            const result = await getSetup();
            this.processSetupData(result);            
            this.blockfrostProjectId = result.blockfrostProjectId || '';
            this.isProjectIdSet = !!this.blockfrostProjectId;
            this.dataChanged = false;
            this.testResult = '';
        } catch (error) {
            this.showToast('Error', 'Failed to load settings: ' + error.body?.message || error.message, 'error');
        } finally {
            this.isLoading = false;
        }        
    }

    async handleBlockfrostSave() {
        if (!this.dataChanged) {
            return;
        }

        this.isLoading = true;
        try {
            await saveBlockfrostProjectId({
                blockfrostProjectId: this.blockfrostProjectId
            });
            this.showMessage = true;
            this.message = 'Blockfrost Project ID saved successfully';
            this.messageVariant = 'success';
            this.showToast('Success', 'Settings saved successfully', 'success');
            await this.loadSetup();
        } catch (error) {
            this.showMessage = true;            
            this.message = 'Error saving settings: ' + error.body?.message || error.message;
            this.messageVariant = 'error';
            this.showToast('Error', 'Failed to save settings: ' + error.body?.message || error.message, 'error');
        } finally {
            this.isLoading = false;
            this.dataChanged = false;            
        }
    }

    async handleBlockfrostRemove() {
        if (!this.isProjectIdSet) {
            return;
        }

        this.isLoading = true;
        try {
            await saveBlockfrostProjectId({
                blockfrostProjectId: null
            });
            this.showMessage = true;
            this.message = 'Blockfrost Project ID removed successfully';
            this.messageVariant = 'success';
            this.showToast('Success', 'Settings removed successfully', 'success');
            await this.loadSetup(); // Refresh to show input again
        } catch (error) {            
            this.message = error.message;
            this.showMessage = true;
            this.message = 'Error removing settings: ' + error.body?.message || error.message;
            this.messageVariant = 'error';
            this.showToast('Error', 'Failed to remove settings: ' + error.body?.message || error.message, 'error');
        } finally {
            this.isLoading = false;
            this.dataChanged = false;            
        }
    }

    async handleTestBlockfrostConfig() {
        this.isLoading = true;
        this.testResult = '';
        try {
            const result = await testBlockfrostConfig();
            this.testResult = JSON.stringify(JSON.parse(result), null, 2);
            this.showMessage = true;
            this.message = 'Blockfrost configuration tested successfully';
            this.messageVariant = 'success';
            this.showToast('Success', 'Configuration test passed', 'success');
        } catch (error) {
            this.testResult = 'Test failed: ' + (error.body?.message || error.message);
            this.showMessage = true;
            this.message = 'Error testing configuration';
            this.messageVariant = 'error';
            this.showToast('Error', 'Failed to test configuration: ' + (error.body?.message || error.message), 'error');
        } finally {
            this.isLoading = false;            
        }
    }

    async handleRefresh() {
        this.isLoading = true;
        try {
            await this.loadSetup();
        } catch (error) {
            const erroMessage = error.body ? error.body.message : error.message;
            this.showToast(erroMessage);
        } finally {
            this.isLoading = false;
        }
    }

    async handlePrivateKey() {
        this.isLoading = true;
        try {
            const result = await generatePrivateKey();
            this.processSetupData(result);

            this.showToast(this.labels.CORE.Success, this.labels.CORE.Success_Info, TOAST_VARIANT.SUCCESS, TOAST_MODE.SUCCESS);
        } catch (error) {
            const erroMessage = error.body ? error.body.message : error.message;
            this.showToast(erroMessage);
        } finally {
            this.isLoading = false;
        }
    }

    async handleEnableLogging() {
        this.isLoading = true;
        try {
            await enableLogging();
            this.showToast(
                this.labels.LOGGING.SetupSuccess,
                this.labels.LOGGING.EnableSuccess,
                TOAST_VARIANT.SUCCESS,
                TOAST_MODE.SUCCESS
            );
        } catch (error) {
            const errorMessage = error.body ? error.body.message : error.message;
            showToast(this, 'Error', errorMessage, TOAST_VARIANT.ERROR, TOAST_MODE.ERROR);
        } finally {
            this.isLoading = false;
        }
    }

    async handleDisableLogging() {
        this.isLoading = true;
        try {
            await disableLogging();
            this.showToast(
                this.labels.LOGGING.SetupSuccess,
                this.labels.LOGGING.DisableSuccess,
                TOAST_VARIANT.SUCCESS,
                TOAST_MODE.SUCCESS
            );
        } catch (error) {
            const errorMessage = error.body ? error.body.message : error.message;
            showToast(this, 'Error', errorMessage, TOAST_VARIANT.ERROR, TOAST_MODE.ERROR);
        } finally {
            this.isLoading = false;
        }
    }

    async connectedCallback() {
        try {
            await this.loadSetup();
        } catch (error) {
            const errorMessage = error.body ? error.body.message : error.message;
            this.showToast(errorMessage);
        } finally {
            this.isLoading = false;
        }
    }

    showToast(title, message, type = TOAST_VARIANT.ERROR, mode = TOAST_MODE.ERROR) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: title,
                message: message,
                variant: type,
                mode: mode
            })
        );
    }
}
