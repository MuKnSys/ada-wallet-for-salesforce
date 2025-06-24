import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import { labels } from './labels';
import { TOAST_VARIANT, TOAST_MODE, STEPS } from 'c/constants';

import getSetup from '@salesforce/apex/AdaWalletsSetupCtrl.getSetup';
import generatePrivateKey from '@salesforce/apex/AdaWalletsSetupCtrl.generatePrivateKey';
import enableLogging from '@salesforce/apex/AdaWalletsSetupCtrl.enableLogging';
import disableLogging from '@salesforce/apex/AdaWalletsSetupCtrl.disableLogging';
import saveBlockfrostProjectId from '@salesforce/apex/AdaWalletsSetupCtrl.saveBlockfrostProjectId';
import testBlockfrostConfig from '@salesforce/apex/AdaWalletsSetupCtrl.testBlockfrostConfig';
import initializeAssets from '@salesforce/apex/AdaAssetInitializer.initializeAssets';

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
            const errorMessage = 'Failed to load settings: ' + error.body ? error.body.message : error.message;
            this.showToast('Error', errorMessage, TOAST_VARIANT.ERROR, TOAST_MODE.ERROR);
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
            this.showToast(this.labels.CORE.Success, 'Blockfrost Project ID saved successfully', TOAST_VARIANT.SUCCESS, TOAST_MODE.SUCCESS);
            await this.loadSetup();
        } catch (error) {
            const errorMessage = 'Failed to save settings: ' + error.body ? error.body.message : error.message;
            this.showToast('Error', errorMessage, TOAST_VARIANT.ERROR, TOAST_MODE.ERROR);
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
            this.showToast(this.labels.CORE.Success, 'Settings removed successfully', TOAST_VARIANT.SUCCESS, TOAST_MODE.SUCCESS);
            await this.loadSetup();
        } catch (error) {
            const errorMessage = 'Failed to remove settings: ' + error.body ? error.body.message : error.message;
            this.showToast('Error', errorMessage, TOAST_VARIANT.ERROR, TOAST_MODE.ERROR);
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
            this.showToast(this.labels.CORE.Success, 'Blockfrost configuration tested successfully', TOAST_VARIANT.SUCCESS, TOAST_MODE.SUCCESS);
        } catch (error) {
            this.testResult = 'Test failed: ' + (error.body?.message || error.message);
            const errorMessage ='Failed to test configuration: ' + error.body ? error.body.message : error.message;
            this.showToast('Error', errorMessage, TOAST_VARIANT.ERROR, TOAST_MODE.ERROR);
        } finally {
            this.isLoading = false;            
        }
    }

    async handleRefresh() {
        this.isLoading = true;
        try {
            await this.loadSetup();
        } catch (error) {
            const errorMessage = error.body ? error.body.message : error.message;
            this.showToast('Error', errorMessage, TOAST_VARIANT.ERROR, TOAST_MODE.ERROR);
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
            const errorMessage = error.body ? error.body.message : error.message;
            this.showToast('Error', errorMessage, TOAST_VARIANT.ERROR, TOAST_MODE.ERROR);
        } finally {
            this.isLoading = false;
        }
    }

    async handleEnableLogging() {
        this.isLoading = true;
        try {
            await enableLogging();
            this.showToast(this.labels.CORE.Success, this.labels.LOGGING.EnableSuccess, TOAST_VARIANT.SUCCESS, TOAST_MODE.SUCCESS);
        } catch (error) {
            const errorMessage = error.body ? error.body.message : error.message;
            this.showToast('Error', errorMessage, TOAST_VARIANT.ERROR, TOAST_MODE.ERROR);
        } finally {
            this.isLoading = false;
        }
    }

    async handleDisableLogging() {
        this.isLoading = true;
        try {
            await disableLogging();
            this.showToast(this.labels.CORE.Success, this.labels.LOGGING.DisableSuccess, TOAST_VARIANT.SUCCESS, TOAST_MODE.SUCCESS);
        } catch (error) {
            const errorMessage = error.body ? error.body.message : error.message;
            this.showToast('Error', errorMessage, TOAST_VARIANT.ERROR, TOAST_MODE.ERROR);
        } finally {
            this.isLoading = false;
        }
    }

    async handleInitializeAssets() {
        this.isLoading = true;
        try {
            await initializeAssets();
            this.showToast(this.labels.CORE.Success, 'ADA Assets initialized', TOAST_VARIANT.SUCCESS, TOAST_MODE.SUCCESS);
        } catch (error) {
            const errorMessage = 'Initialization failed: ' + (error.body?.message || error.message);
            this.showToast('Error', errorMessage, TOAST_VARIANT.ERROR, TOAST_MODE.ERROR);
        } finally {
            this.isLoading = false;
        }
    }

    async connectedCallback() {
        try {
            await this.loadSetup();
        } catch (error) {
            const errorMessage = error.body ? error.body.message : error.message;
            this.showToast('Error', errorMessage, TOAST_VARIANT.ERROR, TOAST_MODE.ERROR);
        } finally {
            this.isLoading = false;
        }
    }

    showToast(title, message, type, mode) {
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
