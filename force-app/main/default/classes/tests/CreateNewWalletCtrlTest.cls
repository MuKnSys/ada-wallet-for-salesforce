@isTest
private class CreateNewWalletCtrlTest {
    private static final String TEST_WALLET_NAME = 'Test Wallet';
    private static final String TEST_ADDRESS = 'addr1qxy2k7y69nj4q7yqymkpm4vthasnqeh9lztr8673x50995q9hhtky6f89qag3v5cngq9gry9zth5k5aww6aswgdq9q7spgqrqv';
    private static final String TEST_PRIVATE_KEY = '0123456789abcdef0123456789abcdef';
    private static final String TEST_PUBLIC_KEY = '0123456789abcdef0123456789abcdef';
    private static final Integer TEST_ACCOUNT_INDEX = 0;
    private static final String TEST_SEED_PHRASE = 'test seed phrase';

    @TestSetup
    static void testData() {
        AdaWalletsService.setPrivateKey(TEST_PRIVATE_KEY);
        
        Wallet_Set__c walletSet = new Wallet_Set__c(
            Wallet_Name__c = 'Test Wallet',
            Seed_Phrase__c = DataEncryptor.encryptHmac(TEST_SEED_PHRASE) // Now stores HMAC
        );
        insert walletSet;        
    }

    @isTest
    static void shouldCreateWalletWhenValidDataProvided() {
        Wallet_Set__c walletSet = [SELECT Id FROM Wallet_Set__c LIMIT 1];
        
        Test.startTest();
        Id walletId = CreateNewWalletCtrl.createWallet(
            walletSet.Id,
            TEST_WALLET_NAME,
            TEST_ADDRESS,
            TEST_PRIVATE_KEY,
            TEST_PUBLIC_KEY,
            TEST_ACCOUNT_INDEX,
            'stake1u98ujxfgvdm2ylac9t3aa6atp3cf3kmjcg8h8weqnj7ad6gq3p9jl'
        );
        Test.stopTest();

        Wallet__c createdWallet = [SELECT Id, Name, Account_Index__c FROM Wallet__c WHERE Id = :walletId];
        
        Assert.areEqual(TEST_WALLET_NAME, createdWallet.Name, 'Wallet name should match');
        Assert.areEqual(TEST_ACCOUNT_INDEX, createdWallet.Account_Index__c, 'Account index should match');
    }

    @isTest
    static void shouldGetWalletByIdWhenValidIdProvided() {
        Wallet_Set__c walletSet = [SELECT Id FROM Wallet_Set__c LIMIT 1];
        Wallet__c wallet = new Wallet__c(
            Wallet_Set__c = walletSet.Id,
            Name = TEST_WALLET_NAME,
            Account_Private_Key__c = DataEncryptor.encrypt(TEST_PRIVATE_KEY),
            Account_Public_Key__c = DataEncryptor.encrypt(TEST_PUBLIC_KEY),
            Account_Index__c = TEST_ACCOUNT_INDEX
        );
        insert wallet;

        Test.startTest();
        Wallet__c retrievedWallet = CreateNewWalletCtrl.getWalletById(wallet.Id);
        Test.stopTest();

        Assert.areEqual(wallet.Id, retrievedWallet.Id, 'Retrieved wallet ID should match');        
    }

    @isTest
    static void shouldGetNextAccountIndexWhenNoWalletsExist() {
        Wallet_Set__c walletSet = [SELECT Id FROM Wallet_Set__c LIMIT 1];

        Test.startTest();
        Integer nextIndex = CreateNewWalletCtrl.getNextAccountIndex(walletSet.Id);
        Test.stopTest();

        Assert.areEqual(0, nextIndex, 'Next account index should be 0 when no wallets exist');
    }

    @isTest
    static void shouldGetNextAccountIndexWhenWalletsExist() {
        Wallet_Set__c walletSet = [SELECT Id FROM Wallet_Set__c LIMIT 1];
        Wallet__c wallet = new Wallet__c(
            Wallet_Set__c = walletSet.Id,
            Name = TEST_WALLET_NAME,
            Account_Private_Key__c = DataEncryptor.encrypt(TEST_PRIVATE_KEY),
            Account_Public_Key__c = DataEncryptor.encrypt(TEST_PUBLIC_KEY),
            Account_Index__c = 0
        );
        insert wallet;

        Test.startTest();
        Integer nextIndex = CreateNewWalletCtrl.getNextAccountIndex(walletSet.Id);
        Test.stopTest();

        Assert.areEqual(1, nextIndex, 'Next account index should be 1 when index 0 is used');
    }

    @isTest
    static void shouldValidateIndexWhenIndexIsValid() {
        Wallet_Set__c walletSet = [SELECT Id FROM Wallet_Set__c LIMIT 1];

        Test.startTest();
        String result = CreateNewWalletCtrl.isIndexValid(walletSet.Id, TEST_ACCOUNT_INDEX);
        Test.stopTest();

        Assert.isNull(result, 'Validation should pass for unused index');
    }

    @isTest
    static void shouldValidateIndexWhenIndexIsInvalid() {
        Wallet_Set__c walletSet = [SELECT Id FROM Wallet_Set__c LIMIT 1];
        Wallet__c wallet = new Wallet__c(
            Wallet_Set__c = walletSet.Id,
            Name = TEST_WALLET_NAME,
            Account_Private_Key__c = DataEncryptor.encrypt(TEST_PRIVATE_KEY),
            Account_Public_Key__c = DataEncryptor.encrypt(TEST_PUBLIC_KEY),
            Account_Index__c = TEST_ACCOUNT_INDEX
        );
        insert wallet;

        Test.startTest();
        String result = CreateNewWalletCtrl.isIndexValid(walletSet.Id, TEST_ACCOUNT_INDEX);
        Test.stopTest();

        Assert.isNotNull(result, 'Validation should fail for used index');
        Assert.isTrue(result.contains('already exists'), 'Error message should indicate index is already in use');
    }

    @isTest
    static void shouldGetEncryptedSeedPhrase() {
        Wallet_Set__c walletSet = [SELECT Id FROM Wallet_Set__c LIMIT 1];

        Test.startTest();
        String result = CreateNewWalletCtrl.getEncryptedSeedPhrase(walletSet.Id);
        Test.stopTest();

        // Note: This test may need to be updated since we now use HMAC instead of encryption
        // The EncryptedDataService.getEncryptedSeedPhrase method should handle HMAC values
        Assert.isNotNull(result, 'Should return a value from EncryptedDataService');
    }

    @isTest
    static void shouldVerifySeedPhraseWhenCorrect() {
        Wallet_Set__c walletSet = [SELECT Id FROM Wallet_Set__c LIMIT 1];

        Test.startTest();
        Boolean result = CreateNewWalletCtrl.verifySeedPhrase(walletSet.Id, TEST_SEED_PHRASE);
        Test.stopTest();

        Assert.isTrue(result, 'Seed phrase verification should pass for correct phrase');
    }

    @isTest
    static void shouldVerifySeedPhraseWhenIncorrect() {
        Wallet_Set__c walletSet = [SELECT Id FROM Wallet_Set__c LIMIT 1];

        Test.startTest();
        Boolean result = CreateNewWalletCtrl.verifySeedPhrase(walletSet.Id, 'incorrect seed phrase');
        Test.stopTest();

        Assert.isFalse(result, 'Seed phrase verification should fail for incorrect phrase');
    }

    @isTest
    static void shouldVerifySeedPhraseWhenPartiallyCorrect() {
        Wallet_Set__c walletSet = [SELECT Id FROM Wallet_Set__c LIMIT 1];

        Test.startTest();
        Boolean result = CreateNewWalletCtrl.verifySeedPhrase(walletSet.Id, 'test seed phrase wrong');
        Test.stopTest();

        Assert.isFalse(result, 'Seed phrase verification should fail for partially correct phrase');
    }

    @isTest
    static void shouldThrowExceptionWhenWalletSetIdIsBlank() {
        Test.startTest();
        try {
            CreateNewWalletCtrl.verifySeedPhrase('', TEST_SEED_PHRASE);
            Assert.fail('Should have thrown an exception');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('Wallet Set ID is required'), 'Error message should indicate Wallet Set ID is required');
        }
        Test.stopTest();
    }

    @isTest
    static void shouldThrowExceptionWhenSeedPhraseIsBlank() {
        Wallet_Set__c walletSet = [SELECT Id FROM Wallet_Set__c LIMIT 1];

        Test.startTest();
        try {
            CreateNewWalletCtrl.verifySeedPhrase(walletSet.Id, '');
            Assert.fail('Should have thrown an exception');
        } catch (AuraHandledException e) {
            Assert.isTrue(e.getMessage().contains('Seed phrase is required'), 'Error message should indicate seed phrase is required');
        }
        Test.stopTest();
    }

    private class BlockfrostServiceMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest request) {
            HTTPResponse response = new HTTPResponse();
            response.setStatusCode(200);
            response.setBody('{"used": true}');
            return response;
        }
    }
} 