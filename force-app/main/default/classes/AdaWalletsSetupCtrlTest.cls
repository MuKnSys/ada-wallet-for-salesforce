@isTest
public class AdaWalletsSetupCtrlTest {
    @isTest
    static void testGetSetup() {        
        String testPrivateKey = '0123456789abcdef0123456789abcdef';
        String testBlockfrostProjectId = 'testProjectId';
        AdaWalletsService.setPrivateKey(testPrivateKey);
        AdaWalletsService.setBlockfrostProjectId(testBlockfrostProjectId);
        
        AdaWalletsSetupCtrl.SetupData setupData = AdaWalletsSetupCtrl.getSetup();
        
        Assert.areEqual(testPrivateKey, setupData.privateKey, 'Private key should match the expected value.');
        Assert.areEqual(testBlockfrostProjectId, setupData.blockfrostProjectId, 'Blockfrost project ID should match the expected value.');
    }

    @isTest
    static void testSaveBlockfrostProjectId() {        
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
        AdaWalletsSetupCtrl.SetupData setupData = AdaWalletsSetupCtrl.generatePrivateKey();
        
        Assert.areNotEqual(null, setupData.privateKey, 'Private key should not be null after generation.');
        Assert.areEqual(setupData.privateKey, AdaWalletsService.getPrivateKey(), 'The generated private key should match the service value.');
    }

    @isTest
    static void testEnableLogging() {        
        AdaWalletsSetupCtrl.enableLogging();
        
        Assert.isTrue(new LoggerService().isLoggingEnabled(), 'Logging should be enabled.');
    }

    @isTest
    static void testDisableLogging() {        
        AdaWalletsSetupCtrl.disableLogging();
        
        Assert.isTrue(!new LoggerService().isLoggingEnabled(), 'Logging should be disabled.');
    }
}