@isTest
private class CreateNewWalletCtrlTest {
    private static final String TEST_WALLET_NAME = 'Test Wallet';
    private static final String TEST_ADDRESS = 'addr1qxy2k7y69nj4q7yqymkpm4vthasnqeh9lztr8673x50995q9hhtky6f89qag3v5cngq9gry9zth5k5aww6aswgdq9q7spgqrqv';
    private static final String TEST_PRIVATE_KEY = EncodingUtil.base64Encode(Crypto.generateAesKey(256));
    private static final String TEST_PUBLIC_KEY = EncodingUtil.base64Encode(Crypto.generateAesKey(256));
    private static final Integer TEST_ACCOUNT_INDEX = 0;
    private static final String TEST_SEED_PHRASE = 'test seed phrase';

    @TestSetup
    static void testData() {
        AdaWalletsService.setPrivateKey(TEST_PRIVATE_KEY);
        AdaWalletsService.setHmacKey(EncodingUtil.base64Encode(Crypto.generateAesKey(256)));
        
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
    static void shouldReturnFalseWhenWalletSetIdIsBlank() {
        Test.startTest();
        Boolean result = CreateNewWalletCtrl.verifySeedPhrase('', TEST_SEED_PHRASE);
        Test.stopTest();
        
        Assert.isFalse(result, 'Should return false for blank wallet set ID');
    }

    @isTest
    static void shouldReturnFalseWhenSeedPhraseIsBlank() {
        Wallet_Set__c walletSet = [SELECT Id FROM Wallet_Set__c LIMIT 1];

        Test.startTest();
        Boolean result = CreateNewWalletCtrl.verifySeedPhrase(walletSet.Id, '');
        Test.stopTest();
        
        Assert.isFalse(result, 'Should return false for blank seed phrase');
    }

    @isTest
    static void shouldThrowExceptionWhenWalletIdIsBlank() {
        Test.startTest();
        try {
            CreateNewWalletCtrl.getWalletById('');
            Assert.fail('Should have thrown an exception');
        } catch (AuraHandledException e) {
            Assert.isTrue(true, 'Exception was thrown as expected');
        }
        Test.stopTest();
    }

    @isTest
    static void shouldThrowExceptionWhenWalletIdIsNull() {
        Test.startTest();
        try {
            CreateNewWalletCtrl.getWalletById(null);
            Assert.fail('Should have thrown an exception');
        } catch (AuraHandledException e) {
            Assert.isTrue(true, 'Exception was thrown as expected');
        }
        Test.stopTest();
    }

    @isTest
    static void shouldThrowExceptionWhenWalletNotFound() {
        Test.startTest();
        try {
            CreateNewWalletCtrl.getWalletById('001000000000000');
            Assert.fail('Should have thrown an exception');
        } catch (AuraHandledException e) {
            Assert.isTrue(true, 'Exception was thrown as expected');
        }
        Test.stopTest();
    }

    @isTest
    static void shouldCheckAddressUsageOnly() {
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new BlockfrostServiceMock());
        
        Map<String, Object> result = CreateNewWalletCtrl.checkAddressUsageOnly(TEST_ADDRESS);
        Test.stopTest();
        
        Assert.isNotNull(result, 'Should return address usage result');
        Assert.isTrue(result.containsKey('address'), 'Result should contain address');
        Assert.isTrue(result.containsKey('isUsed'), 'Result should contain isUsed flag');
        Assert.isTrue(result.containsKey('checkMethod'), 'Result should contain check method');
    }

    @isTest
    static void shouldCreateUTXOAddressesBulk() {
        Wallet_Set__c walletSet = [SELECT Id FROM Wallet_Set__c LIMIT 1];
        Wallet__c wallet = new Wallet__c(
            Wallet_Set__c = walletSet.Id,
            Name = TEST_WALLET_NAME,
            Account_Private_Key__c = DataEncryptor.encrypt(TEST_PRIVATE_KEY),
            Account_Public_Key__c = DataEncryptor.encrypt(TEST_PUBLIC_KEY),
            Account_Index__c = TEST_ACCOUNT_INDEX
        );
        insert wallet;

        List<CreateNewWalletCtrl.UTXOAddressData> receivingAddresses = new List<CreateNewWalletCtrl.UTXOAddressData>();
        CreateNewWalletCtrl.UTXOAddressData receivingAddr = new CreateNewWalletCtrl.UTXOAddressData();
        receivingAddr.index = 0;
        receivingAddr.publicKey = 'testPublicKey';
        receivingAddr.privateKey = 'testPrivateKey';
        receivingAddr.address = TEST_ADDRESS;
        receivingAddr.paymentKeyHash = 'testHash';
        receivingAddr.path = 'm/1852\'/1815\'/0\'/0/0';
        receivingAddresses.add(receivingAddr);

        List<CreateNewWalletCtrl.UTXOAddressData> changeAddresses = new List<CreateNewWalletCtrl.UTXOAddressData>();
        CreateNewWalletCtrl.UTXOAddressData changeAddr = new CreateNewWalletCtrl.UTXOAddressData();
        changeAddr.index = 0;
        changeAddr.publicKey = 'testPublicKey2';
        changeAddr.privateKey = 'testPrivateKey2';
        changeAddr.address = TEST_ADDRESS;
        changeAddr.paymentKeyHash = 'testHash2';
        changeAddr.path = 'm/1852\'/1815\'/0\'/1/0';
        changeAddresses.add(changeAddr);

        Test.startTest();
        Map<String, Object> result = CreateNewWalletCtrl.createUTXOAddressesBulk(wallet.Id, receivingAddresses, changeAddresses);
        Test.stopTest();
        
        Assert.isNotNull(result, 'Should return bulk creation result');
        Assert.isTrue(result.containsKey('success'), 'Result should contain success flag');
        Assert.isTrue(result.containsKey('walletId'), 'Result should contain wallet ID');
        Assert.isTrue(result.containsKey('receivingAddresses'), 'Result should contain receiving addresses');
        Assert.isTrue(result.containsKey('changeAddresses'), 'Result should contain change addresses');
    }

    @isTest
    static void shouldThrowExceptionWhenAddressListsAreNull() {
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
        try {
            CreateNewWalletCtrl.createUTXOAddressesBulk(wallet.Id, null, null);
            Assert.fail('Should have thrown an exception');
        } catch (AuraHandledException e) {
            Assert.isTrue(true, 'Exception was thrown as expected');
        }
        Test.stopTest();
    }

    @isTest
    static void shouldThrowExceptionWhenCreateWalletWithInvalidData() {
        Wallet_Set__c walletSet = [SELECT Id FROM Wallet_Set__c LIMIT 1];
        
        Test.startTest();
        try {
            CreateNewWalletCtrl.createWallet(
                'invalid-wallet-set-id', // Invalid wallet set ID
                TEST_WALLET_NAME,
                TEST_ADDRESS,
                TEST_PRIVATE_KEY,
                TEST_PUBLIC_KEY,
                TEST_ACCOUNT_INDEX,
                'stake1u98ujxfgvdm2ylac9t3aa6atp3cf3kmjcg8h8weqnj7ad6gq3p9jl'
            );
            Assert.fail('Should have thrown an exception');
        } catch (AuraHandledException e) {
            Assert.isTrue(true, 'Exception was thrown as expected');
        }
        Test.stopTest();
    }

    @isTest
    static void shouldGetEncryptedSeedPhraseWithException() {
        Test.startTest();
        try {
            CreateNewWalletCtrl.getEncryptedSeedPhrase('001000000000000');
            Assert.fail('Should have thrown an exception');
        } catch (AuraHandledException e) {
            Assert.isTrue(true, 'Exception was thrown as expected');
        }
        Test.stopTest();
    }

    @isTest
    static void shouldCheckAddressUsageOnlyWithException() {
        Test.startTest();
        try {
            CreateNewWalletCtrl.checkAddressUsageOnly('');
            Assert.fail('Should have thrown an exception');
        } catch (AuraHandledException e) {
            Assert.isTrue(true, 'Exception was thrown as expected');
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