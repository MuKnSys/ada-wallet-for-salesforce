@isTest
public class AdaWalletsSetupCtrlTest {
    
    private static void resetSettings() {
        AdaSettings__c adaSettings = AdaSettings__c.getOrgDefaults();
        if (adaSettings.Id == null) {
            adaSettings = new AdaSettings__c();
        }
        adaSettings.Private_Key__c = null;
        adaSettings.Hmac_Key__c = null;
        adaSettings.BlockfrostProjectId__c = null;
        adaSettings.Transaction_approvals_enabled__c = false;
        upsert adaSettings;
    }
    
    @testSetup
    static void testData() {
        resetSettings();
    }

    @isTest
    static void testGetSetup() {        
        resetSettings();
        String testPrivateKey = EncodingUtil.base64Encode(Crypto.generateAesKey(256));
        String testBlockfrostProjectId = 'testProjectId';
        AdaWalletsService.setPrivateKey(testPrivateKey);
        AdaWalletsService.setBlockfrostProjectId(testBlockfrostProjectId);
        
        AdaWalletsSetupCtrl.SetupData setupData = AdaWalletsSetupCtrl.getSetup();
        
        Assert.areEqual(testPrivateKey, setupData.privateKey, 'Private key should match the expected value.');
        Assert.areEqual(testBlockfrostProjectId, setupData.blockfrostProjectId, 'Blockfrost project ID should match the expected value.');
    }

    @isTest
    static void testSaveBlockfrostProjectId() {        
        resetSettings();
        String newProjectId = 'newTestProjectId';
        
        AdaWalletsSetupCtrl.saveBlockfrostProjectId(newProjectId);
        String savedProjectId = AdaWalletsService.getBlockfrostProjectId();
        
        Assert.areEqual(newProjectId, savedProjectId, 'The saved Blockfrost project ID should match the new value.');
    }

    @isTest
    static void testBlockfrostConfig() {
        Test.startTest();
        BlockfrostServiceHttpCalloutMock httpMock = new BlockfrostServiceHttpCalloutMock();        
        Test.setMock(HttpCalloutMock.class, httpMock);

        try {
            String config = AdaWalletsSetupCtrl.testBlockfrostConfig();
            Assert.areNotEqual(null, config, 'Blockfrost config should not be null.');            
        } catch (Exception e) {
            Assert.isTrue(false, 'Expected no exception, but got: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testGeneratePrivateKey() {        
        resetSettings();
        Test.startTest();
        AdaWalletsSetupCtrl.SetupData setupData = AdaWalletsSetupCtrl.generatePrivateAndHmacKey();
        Test.stopTest();
        
        Assert.areNotEqual(null, setupData.privateKey, 'Private key should not be null after generation.');
        Assert.areEqual(setupData.privateKey, AdaWalletsService.getPrivateKey(), 'The generated private key should match the service value.');
        Assert.areNotEqual(null, setupData.isEncryptionKeySet, 'Encryption key set flag should not be null.');
        Assert.areNotEqual(null, setupData.isHmacKeySet, 'Hmac key set flag should not be null.');
    }

    @isTest
    static void testGeneratePrivateKeyWhenAlreadySet() {
        resetSettings();
        String existingPrivateKey = EncodingUtil.base64Encode(Crypto.generateAesKey(256));
        String existingHmacKey = EncodingUtil.base64Encode(Crypto.generateAesKey(256));
        AdaWalletsService.setPrivateKey(existingPrivateKey);
        AdaWalletsService.setHmacKey(existingHmacKey);
        
        Test.startTest();
        try {
            AdaWalletsSetupCtrl.generatePrivateAndHmacKey();
            Assert.isTrue(false, 'Expected exception when keys are already set');
        } catch (AuraHandledException e) {
            Assert.isTrue(true, 'Exception was thrown as expected');
        }
        Test.stopTest();
    }

    @isTest
    static void testGeneratePrivateKeyWhenOnlyEncryptionKeySet() {
        resetSettings();
        String existingPrivateKey = EncodingUtil.base64Encode(Crypto.generateAesKey(256));
        AdaWalletsService.setPrivateKey(existingPrivateKey);
        
        Test.startTest();
        try {
            AdaWalletsSetupCtrl.generatePrivateAndHmacKey();
            Assert.isTrue(false, 'Expected exception when encryption key is already set');
        } catch (AuraHandledException e) {
            Assert.isTrue(true, 'Exception was thrown as expected');
        }
        Test.stopTest();
    }

    @isTest
    static void testGeneratePrivateKeyWhenOnlyHmacKeySet() {
        resetSettings();
        String existingHmacKey = EncodingUtil.base64Encode(Crypto.generateAesKey(256));
        AdaWalletsService.setHmacKey(existingHmacKey);
        
        Test.startTest();
        try {
            AdaWalletsSetupCtrl.generatePrivateAndHmacKey();
            Assert.isTrue(false, 'Expected exception when hmac key is already set');
        } catch (AuraHandledException e) {
            Assert.isTrue(true, 'Exception was thrown as expected');
        }
        Test.stopTest();
    }

    @isTest
    static void testEnableLogging() {        
        AdaWalletsSetupCtrl.enableLogging();
        
        Assert.isTrue(new LoggerServiceADA().isLoggingEnabled(), 'Logging should be enabled.');
    }

    @isTest
    static void testDisableLogging() {        
        AdaWalletsSetupCtrl.disableLogging();
        
        Assert.isTrue(!new LoggerServiceADA().isLoggingEnabled(), 'Logging should be disabled.');
    }

    @isTest
    static void testUpdateTransactionApprovalsEnable() {
        resetSettings();
        
        Test.startTest();
        AdaWalletsSetupCtrl.updateTransactionApprovals(true);
        Test.stopTest();
        
        Assert.isTrue(AdaWalletsService.isTransactionApprovalsEnabled(), 'Transaction approvals should be enabled.');
    }

    @isTest
    static void testUpdateTransactionApprovalsDisable() {
        resetSettings();
        
        Test.startTest();
        AdaWalletsSetupCtrl.updateTransactionApprovals(false);
        Test.stopTest();
        
        Assert.isTrue(!AdaWalletsService.isTransactionApprovalsEnabled(), 'Transaction approvals should be disabled.');
    }
}