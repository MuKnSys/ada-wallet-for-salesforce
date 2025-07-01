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
            Seed_Phrase__c = DataEncryptor.encrypt(TEST_SEED_PHRASE)
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
            TEST_ACCOUNT_INDEX
        );
        Test.stopTest();

        Wallet__c createdWallet = [SELECT Id, Name, Address__c, Account_Index__c FROM Wallet__c WHERE Id = :walletId];
        
        Assert.areEqual(TEST_WALLET_NAME, createdWallet.Name, 'Wallet name should match');
        Assert.areEqual(TEST_ADDRESS, createdWallet.Address__c, 'Wallet address should match');
        Assert.areEqual(TEST_ACCOUNT_INDEX, createdWallet.Account_Index__c, 'Account index should match');
    }

    @isTest
    static void shouldGetWalletByIdWhenValidIdProvided() {
        Wallet_Set__c walletSet = [SELECT Id FROM Wallet_Set__c LIMIT 1];
        Wallet__c wallet = new Wallet__c(
            Wallet_Set__c = walletSet.Id,
            Name = TEST_WALLET_NAME,
            Address__c = TEST_ADDRESS,
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
            Address__c = TEST_ADDRESS,
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
            Address__c = TEST_ADDRESS,
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
    static void shouldGetDecryptedSeedPhrase() {
        Wallet_Set__c walletSet = [SELECT Id FROM Wallet_Set__c LIMIT 1];

        Test.startTest();
        String result = CreateNewWalletCtrl.getDecryptedSeedPhrase(walletSet.Id);
        Test.stopTest();

        Assert.areEqual(TEST_SEED_PHRASE, result, 'Decrypted seed phrase should match mock value');
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