@isTest
public class WalletSetCtrlTest {
    private static final String TEST_WALLET_NAME = 'Test Wallet';
    private static final String TEST_SEED_PHRASE = 'test seed phrase for wallet';
    private static final String TEST_PRIVATE_KEY = EncodingUtil.base64Encode(Crypto.generateAesKey(256));
    private static final String TEST_HMAC_KEY = EncodingUtil.base64Encode(Crypto.generateAesKey(256));
    
    @testSetup
    static void testData() {
        AdaWalletsService.setPrivateKey(TEST_PRIVATE_KEY);
        AdaWalletsService.setHmacKey(TEST_HMAC_KEY);
    }
    
    @isTest
    static void testCreateWalletSet() {        
        Test.startTest();
            Id walletSetId = WalletSetCtrl.createWalletSet(TEST_WALLET_NAME, TEST_SEED_PHRASE);
        Test.stopTest();

        Assert.areNotEqual(null, walletSetId, 'Wallet Set ID should not be null.');
        Wallet_Set__c walletSet = [SELECT Id, Wallet_Name__c, Seed_Phrase__c FROM Wallet_Set__c WHERE Id = :walletSetId];
        Assert.areEqual(TEST_WALLET_NAME, walletSet.Wallet_Name__c, 'Wallet name should match the input.');
        Assert.isNotNull(walletSet.Seed_Phrase__c, 'Seed phrase should be encrypted and stored');
    }
    
    @isTest
    static void testCreateWalletSetWithEmptyName() {
        Test.startTest();
            Id walletSetId = WalletSetCtrl.createWalletSet('', TEST_SEED_PHRASE);
        Test.stopTest();

        Assert.areNotEqual(null, walletSetId, 'Should create wallet set even with empty name');
        Wallet_Set__c walletSet = [SELECT Id, Wallet_Name__c FROM Wallet_Set__c WHERE Id = :walletSetId];
        Assert.isNull(walletSet.Wallet_Name__c, 'Empty name should be stored as null');
    }
    
    @isTest
    static void testCreateWalletSetWithNullName() {
        Test.startTest();
            Id walletSetId = WalletSetCtrl.createWalletSet(null, TEST_SEED_PHRASE);
        Test.stopTest();

        Assert.areNotEqual(null, walletSetId, 'Should create wallet set even with null name');
        Wallet_Set__c walletSet = [SELECT Id, Wallet_Name__c FROM Wallet_Set__c WHERE Id = :walletSetId];
        Assert.isNull(walletSet.Wallet_Name__c, 'Null name should be stored as null');
    }
    
    @isTest
    static void testCreateWalletSetWithEmptySeedPhrase() {
        Test.startTest();
            try {
                WalletSetCtrl.createWalletSet(TEST_WALLET_NAME, '');
                Assert.fail('Should throw exception for empty seed phrase');
            } catch (AuraHandledException e) {
                Assert.isNotNull(e.getMessage(), 'Should throw exception with message');
            }
        Test.stopTest();
    }
    
    @isTest
    static void testCreateWalletSetWithNullSeedPhrase() {
        Test.startTest();
            try {
                WalletSetCtrl.createWalletSet(TEST_WALLET_NAME, null);
                Assert.fail('Should throw exception for null seed phrase');
            } catch (AuraHandledException e) {
                Assert.isNotNull(e.getMessage(), 'Should throw exception with message');
            }
        Test.stopTest();
    }
    
    @isTest
    static void testCreateWalletSetWithLongName() {
        String longName = 'A'.repeat(80);
        
        Test.startTest();
            Id walletSetId = WalletSetCtrl.createWalletSet(longName, TEST_SEED_PHRASE);
        Test.stopTest();

        Assert.areNotEqual(null, walletSetId, 'Wallet Set ID should not be null.');
        Wallet_Set__c walletSet = [SELECT Id, Wallet_Name__c FROM Wallet_Set__c WHERE Id = :walletSetId];
        Assert.areEqual(longName, walletSet.Wallet_Name__c, 'Long wallet name should be stored correctly');
    }
    
    @isTest
    static void testCreateWalletSetWithSpecialCharacters() {
        String specialName = 'Test Wallet @#$%^&*()';
        String specialSeedPhrase = 'test seed phrase with special chars !@#$%^&*()';
        
        Test.startTest();
            Id walletSetId = WalletSetCtrl.createWalletSet(specialName, specialSeedPhrase);
        Test.stopTest();

        Assert.areNotEqual(null, walletSetId, 'Wallet Set ID should not be null.');
        Wallet_Set__c walletSet = [SELECT Id, Wallet_Name__c FROM Wallet_Set__c WHERE Id = :walletSetId];
        Assert.areEqual(specialName, walletSet.Wallet_Name__c, 'Special characters should be handled correctly');
    }
    
    @isTest
    static void testCreateWalletSetWithUnicodeCharacters() {
        String unicodeName = 'Test Wallet 测试 кошелек';
        String unicodeSeedPhrase = 'test seed phrase with unicode 测试 кошелек';
        
        Test.startTest();
            Id walletSetId = WalletSetCtrl.createWalletSet(unicodeName, unicodeSeedPhrase);
        Test.stopTest();

        Assert.areNotEqual(null, walletSetId, 'Wallet Set ID should not be null.');
        Wallet_Set__c walletSet = [SELECT Id, Wallet_Name__c FROM Wallet_Set__c WHERE Id = :walletSetId];
        Assert.areEqual(unicodeName, walletSet.Wallet_Name__c, 'Unicode characters should be handled correctly');
    }
    
    @isTest
    static void testCreateMultipleWalletSets() {
        List<Id> walletSetIds = new List<Id>();
        
        Test.startTest();
            for (Integer i = 0; i < 5; i++) {
                Id walletSetId = WalletSetCtrl.createWalletSet(TEST_WALLET_NAME + ' ' + i, TEST_SEED_PHRASE + ' ' + i);
                walletSetIds.add(walletSetId);
            }
        Test.stopTest();

        Assert.areEqual(5, walletSetIds.size(), 'Should create 5 wallet sets');
        
        List<Wallet_Set__c> walletSets = [SELECT Id, Wallet_Name__c FROM Wallet_Set__c WHERE Id IN :walletSetIds];
        Assert.areEqual(5, walletSets.size(), 'Should retrieve all created wallet sets');
    }
    
    @isTest
    static void testCreateWalletSetWithWhitespace() {
        String nameWithWhitespace = '  Test Wallet  ';
        String seedPhraseWithWhitespace = '  test seed phrase  ';
        
        Test.startTest();
            Id walletSetId = WalletSetCtrl.createWalletSet(nameWithWhitespace, seedPhraseWithWhitespace);
        Test.stopTest();

        Assert.areNotEqual(null, walletSetId, 'Wallet Set ID should not be null.');
        Wallet_Set__c walletSet = [SELECT Id, Wallet_Name__c FROM Wallet_Set__c WHERE Id = :walletSetId];
        Assert.areEqual('Test Wallet', walletSet.Wallet_Name__c, 'Whitespace should be trimmed by Salesforce');
    }
    
    @isTest
    static void testCreateWalletSetWithVeryLongSeedPhrase() {
        String longSeedPhrase = 'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12 word13 word14 word15 word16 word17 word18 word19 word20 word21 word22 word23 word24';
        
        Test.startTest();
            Id walletSetId = WalletSetCtrl.createWalletSet(TEST_WALLET_NAME, longSeedPhrase);
        Test.stopTest();

        Assert.areNotEqual(null, walletSetId, 'Wallet Set ID should not be null.');
        Wallet_Set__c walletSet = [SELECT Id, Seed_Phrase__c FROM Wallet_Set__c WHERE Id = :walletSetId];
        Assert.isNotNull(walletSet.Seed_Phrase__c, 'Long seed phrase should be encrypted and stored');
    }
}