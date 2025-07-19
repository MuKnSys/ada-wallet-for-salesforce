@isTest
private class UTXOControllerTest {
    private static final String TEST_PRIVATE_KEY = EncodingUtil.base64Encode(Crypto.generateAesKey(256));
    private static final String TEST_SEED_PHRASE = 'test seed phrase';
    
    @testSetup
    private static void testData() {
        AdaWalletsService.setPrivateKey(TEST_PRIVATE_KEY);
        AdaWalletsService.setHmacKey(EncodingUtil.base64Encode(Crypto.generateAesKey(256)));

        Wallet_Set__c walletSet = new Wallet_Set__c(
            Wallet_Name__c = 'Test Wallet',
            Seed_Phrase__c = DataEncryptor.encryptHmac(TEST_SEED_PHRASE)
        );
        insert walletSet;
        
        Wallet__c wallet = new Wallet__c(
            Name = 'Test Wallet',
            Wallet_Set__c = walletSet.Id
        );
        insert wallet;
    }
    
    @isTest
    private static void testGetWallet() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        
        Test.startTest();
            Wallet__c result = UTXOController.getWallet(wallet.Id);
        Test.stopTest();
        
        Assert.areEqual(wallet.Id, result.Id, 'Wallet ID should match');
    }
    
    @isTest
    static void testGetEncryptedSeedPhrase() {
        Wallet_Set__c walletSet = [SELECT Id FROM Wallet_Set__c LIMIT 1];

        Test.startTest();
        String result = UTXOController.getEncryptedSeedPhrase(walletSet.Id);
        Test.stopTest();

        Assert.isNotNull(result, 'Should return encrypted seed phrase');
        Assert.areNotEqual(TEST_SEED_PHRASE, result, 'Should return encrypted value, not plain text');
    }
    
    @isTest
    private static void testGetUTXOAddresses() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        
        UTXO_Address__c utxoAddress = new UTXO_Address__c(
            Wallet__c = wallet.Id,
            Address__c = 'testAddress',
            Index__c = 0,
            Public_Key__c = 'testPublicKey',
            Payment_Key_Hash__c = 'testPaymentKeyHash',
            Path__c = 'testPath',
            Private_Key__c = 'testPrivateKey',
            Type__c = '0'
        );
        insert utxoAddress;
        
        Test.startTest();
            List<UTXO_Address__c> result = UTXOController.getUTXOAddresses(wallet.Id);
        Test.stopTest();
        
        Assert.areEqual(1, result.size(), 'Should return 1 address');
        Assert.areEqual('testAddress', result[0].Address__c, 'Address should match');
        Assert.areEqual(0, result[0].Index__c, 'Index should match');
        Assert.areEqual('testPublicKey', result[0].Public_Key__c, 'Public key should match');
        Assert.areEqual('testPaymentKeyHash', result[0].Payment_Key_Hash__c, 'Payment key hash should match');
        Assert.areEqual('testPath', result[0].Path__c, 'Path should match');
        Assert.areEqual('testPrivateKey', result[0].Private_Key__c, 'Private key should match');
        Assert.areEqual('0', result[0].Type__c, 'Type should match');
    }
    
    @isTest
    private static void testGetUserPermissions() {
        Test.startTest();
            List<String> result = UTXOController.getUserPermissions();
        Test.stopTest();
        
        Assert.isNotNull(result, 'Permissions should not be null');
    }
    
    @isTest
    private static void testGetNextUTXOIndex() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        
        UTXO_Address__c utxoAddress = new UTXO_Address__c(
            Wallet__c = wallet.Id,
            Address__c = 'testAddress',
            Index__c = 0,
            Public_Key__c = 'testPublicKey',
            Payment_Key_Hash__c = 'testPaymentKeyHash',
            Path__c = 'testPath',
            Private_Key__c = 'testPrivateKey',
            Type__c = '0'
        );
        insert utxoAddress;
        
        Test.startTest();
            Integer result = UTXOController.getNextUTXOIndex(wallet.Id, '0');
        Test.stopTest();
        
        Assert.areEqual(1, result, 'Next index should match');
    }
    
    @isTest
    private static void testAddReceivingAddress() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];

        Map<String,Object> receivingAddress = new Map<String,Object>{
            'index' => 0,
            'address' => 'receivingAddress',
            'publicKey' => 'publicKey',
            'paymentKeyHash' => 'paymentKeyHash',
            'path' => 'path',
            'privateKey' => 'privateKey'
        };
        
        Test.startTest();
            String receivingId = UTXOController.addReceivingUTXOAddress(wallet.Id, receivingAddress);
        Test.stopTest();
        
        UTXO_Address__c createdReceiving = [SELECT Id, Address__c, Index__c, Public_Key__c, Payment_Key_Hash__c, Path__c, Private_Key__c, Type__c 
                                          FROM UTXO_Address__c WHERE Id = :receivingId];
        
        Assert.areEqual('receivingAddress', createdReceiving.Address__c, 'Address should match');
        Assert.areEqual(0, createdReceiving.Index__c, 'Index should match');
        Assert.areEqual('publicKey', createdReceiving.Public_Key__c, 'Public key should match');
        Assert.areEqual('paymentKeyHash', createdReceiving.Payment_Key_Hash__c, 'Payment key hash should match');
        Assert.areEqual('path', createdReceiving.Path__c, 'Path should match');
        Assert.areEqual('privateKey', createdReceiving.Private_Key__c, 'Private key should match');
        Assert.areEqual('0', createdReceiving.Type__c, 'Type should match');
    }

    @isTest
    private static void testAddChangeAddress() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];

        Map<String,Object> changeAddress = new Map<String,Object>{
            'index' => 0,
            'address' => 'changeAddress',
            'publicKey' => 'publicKey2',
            'paymentKeyHash' => 'paymentKeyHash2',
            'path' => 'path2',
            'privateKey' => 'privateKey2'
        };
        
        Test.startTest();
            String changeId = UTXOController.addChangeUTXOAddress(wallet.Id, changeAddress);
        Test.stopTest();
        
        UTXO_Address__c createdChange = [SELECT Id, Address__c, Index__c, Public_Key__c, Payment_Key_Hash__c, Path__c, Private_Key__c, Type__c 
                                       FROM UTXO_Address__c WHERE Id = :changeId];
        
        Assert.areEqual('changeAddress', createdChange.Address__c, 'Address should match');
        Assert.areEqual(0, createdChange.Index__c, 'Index should match');
        Assert.areEqual('publicKey2', createdChange.Public_Key__c, 'Public key should match');
        Assert.areEqual('paymentKeyHash2', createdChange.Payment_Key_Hash__c, 'Payment key hash should match');
        Assert.areEqual('path2', createdChange.Path__c, 'Path should match');
        Assert.areEqual('privateKey2', createdChange.Private_Key__c, 'Private key should match');
        Assert.areEqual('1', createdChange.Type__c, 'Type should match');
    }

    @isTest
    private static void testSyncAssetsAndTransactions() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        
        UTXO_Address__c utxoAddress = new UTXO_Address__c(
            Wallet__c = wallet.Id,
            Address__c = 'testAddress',
            Index__c = 0,
            Public_Key__c = 'testPublicKey',
            Payment_Key_Hash__c = 'testPaymentKeyHash',
            Path__c = 'testPath',
            Private_Key__c = 'testPrivateKey',
            Type__c = '0'
        );
        insert utxoAddress;
        
        Test.startTest();
            Map<String, Object> result = UTXOController.syncAssetsAndTransactions(utxoAddress.Id);
        Test.stopTest();
        
        Assert.isNotNull(result, 'Should return sync results');
    }

    @isTest
    private static void testSetAddressesUsed() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        
        UTXO_Address__c utxoAddress = new UTXO_Address__c(
            Wallet__c = wallet.Id,
            Address__c = 'testAddress',
            Index__c = 0,
            Public_Key__c = 'testPublicKey',
            Payment_Key_Hash__c = 'testPaymentKeyHash',
            Path__c = 'testPath',
            Private_Key__c = 'testPrivateKey',
            Type__c = '0'
        );
        insert utxoAddress;
        
        Test.startTest();
            UTXOController.setAddressesUsed(new List<Id>{utxoAddress.Id});
        Test.stopTest();
        
        UTXO_Address__c updatedAddress = [SELECT Id, Is_Used__c FROM UTXO_Address__c WHERE Id = :utxoAddress.Id];
        Assert.isTrue(updatedAddress.Is_Used__c, 'Address should be marked as used');
    }

    @isTest
    private static void testGetNextUTXOIndexWithNoAddresses() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        
        Test.startTest();
            Integer result = UTXOController.getNextUTXOIndex(wallet.Id, '0');
        Test.stopTest();
        
        Assert.areEqual(0, result, 'Should return 0 when no addresses exist');
    }

    @isTest
    private static void testGetNextUTXOIndexWithExistingAddresses() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        
        UTXO_Address__c utxoAddress1 = new UTXO_Address__c(
            Wallet__c = wallet.Id,
            Address__c = 'testAddress1',
            Index__c = 0,
            Public_Key__c = 'testPublicKey1',
            Payment_Key_Hash__c = 'testPaymentKeyHash1',
            Path__c = 'testPath1',
            Private_Key__c = 'testPrivateKey1',
            Type__c = '0'
        );
        insert utxoAddress1;
        
        UTXO_Address__c utxoAddress2 = new UTXO_Address__c(
            Wallet__c = wallet.Id,
            Address__c = 'testAddress2',
            Index__c = 5,
            Public_Key__c = 'testPublicKey2',
            Payment_Key_Hash__c = 'testPaymentKeyHash2',
            Path__c = 'testPath2',
            Private_Key__c = 'testPrivateKey2',
            Type__c = '0'
        );
        insert utxoAddress2;
        
        Test.startTest();
            Integer result = UTXOController.getNextUTXOIndex(wallet.Id, '0');
        Test.stopTest();
        
        Assert.areEqual(6, result, 'Should return next index after highest existing index');
    }

    @isTest
    private static void testGetNextUTXOIndexInvalidType() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        
        Test.startTest();
            try {
                UTXOController.getNextUTXOIndex(wallet.Id, 'invalid');
                Assert.fail('Should throw exception for invalid type');
            } catch (AuraHandledException e) {
                Assert.isNotNull(e.getMessage(), 'Should throw exception with message');
            }
        Test.stopTest();
    }

    @isTest
    private static void testGetNextUTXOIndexNullType() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        
        Test.startTest();
            try {
                UTXOController.getNextUTXOIndex(wallet.Id, null);
                Assert.fail('Should throw exception for null type');
            } catch (AuraHandledException e) {
                Assert.isNotNull(e.getMessage(), 'Should throw exception with message');
            }
        Test.stopTest();
    }

    @isTest
    private static void testAddReceivingAddressNullAddress() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        
        Test.startTest();
            try {
                UTXOController.addReceivingUTXOAddress(wallet.Id, null);
                Assert.fail('Should throw exception for null address');
            } catch (AuraHandledException e) {
                Assert.isNotNull(e.getMessage(), 'Should throw exception with message');
            }
        Test.stopTest();
    }

    @isTest
    private static void testAddReceivingAddressInvalidData() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        
        Test.startTest();
            try {
                UTXOController.addReceivingUTXOAddress(wallet.Id, null);
                Assert.fail('Should throw exception for invalid address data');
            } catch (AuraHandledException e) {
                Assert.isNotNull(e.getMessage(), 'Should throw exception with message');
            }
        Test.stopTest();
    }

    @isTest
    private static void testAddChangeAddressNullAddress() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        
        Test.startTest();
            try {
                UTXOController.addChangeUTXOAddress(wallet.Id, null);
                Assert.fail('Should throw exception for null address');
            } catch (AuraHandledException e) {
                Assert.isNotNull(e.getMessage(), 'Should throw exception with message');
            }
        Test.stopTest();
    }

    @isTest
    private static void testAddChangeAddressInvalidData() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        
        Test.startTest();
            try {
                UTXOController.addChangeUTXOAddress(wallet.Id, null);
                Assert.fail('Should throw exception for invalid address data');
            } catch (AuraHandledException e) {
                Assert.isNotNull(e.getMessage(), 'Should throw exception with message');
            }
        Test.stopTest();
    }

    @isTest
    private static void testAddReceivingAddressWithNullPrivateKey() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];

        Map<String,Object> receivingAddress = new Map<String,Object>{
            'index' => 0,
            'address' => 'receivingAddress',
            'publicKey' => 'publicKey',
            'paymentKeyHash' => 'paymentKeyHash',
            'path' => 'path',
            'privateKey' => null
        };
        
        Test.startTest();
            String receivingId = UTXOController.addReceivingUTXOAddress(wallet.Id, receivingAddress);
        Test.stopTest();
        
        UTXO_Address__c createdReceiving = [SELECT Id, Private_Key__c FROM UTXO_Address__c WHERE Id = :receivingId];
        Assert.isNull(createdReceiving.Private_Key__c, 'Private key should be null when not provided');
    }

    @isTest
    private static void testAddChangeAddressWithNullPrivateKey() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];

        Map<String,Object> changeAddress = new Map<String,Object>{
            'index' => 0,
            'address' => 'changeAddress',
            'publicKey' => 'publicKey2',
            'paymentKeyHash' => 'paymentKeyHash2',
            'path' => 'path2',
            'privateKey' => null
        };
        
        Test.startTest();
            String changeId = UTXOController.addChangeUTXOAddress(wallet.Id, changeAddress);
        Test.stopTest();
        
        UTXO_Address__c createdChange = [SELECT Id, Private_Key__c FROM UTXO_Address__c WHERE Id = :changeId];
        Assert.isNull(createdChange.Private_Key__c, 'Private key should be null when not provided');
    }

    @isTest
    private static void testGetWalletInvalidId() {
        Test.startTest();
            try {
                UTXOController.getWallet('001000000000000');
                Assert.fail('Should throw exception for invalid wallet ID');
            } catch (AuraHandledException e) {
                Assert.isNotNull(e.getMessage(), 'Should throw exception with message');
            }
        Test.stopTest();
    }

    @isTest
    private static void testGetEncryptedSeedPhraseInvalidId() {
        Test.startTest();
            try {
                UTXOController.getEncryptedSeedPhrase('001000000000000');
                Assert.fail('Should throw exception for invalid wallet set ID');
            } catch (AuraHandledException e) {
                Assert.isNotNull(e.getMessage(), 'Should throw exception with message');
            }
        Test.stopTest();
    }

    @isTest
    private static void testGetUTXOAddressesInvalidId() {
        Test.startTest();
            List<UTXO_Address__c> result = UTXOController.getUTXOAddresses('001000000000000');
        Test.stopTest();
        
        Assert.areEqual(0, result.size(), 'Should return empty list for invalid wallet ID');
    }

    @isTest
    private static void testSyncAssetsAndTransactionsInvalidId() {
        Test.startTest();
            Map<String, Object> result = UTXOController.syncAssetsAndTransactions('001000000000000');
        Test.stopTest();
        
        Assert.isNotNull(result, 'Should return result map even for invalid ID');
    }

    @isTest
    private static void testSetAddressesUsedInvalidId() {
        Test.startTest();
            try {
                UTXOController.setAddressesUsed(new List<Id>{'001000000000000'});
                Assert.fail('Should throw exception for invalid UTXO address ID');
            } catch (AuraHandledException e) {
                Assert.isNotNull(e.getMessage(), 'Should throw exception with message');
            }
        Test.stopTest();
    }

    @isTest
    private static void testSetAddressesUsedEmptyList() {
        Test.startTest();
            UTXOController.setAddressesUsed(new List<Id>());
        Test.stopTest();
        
        Assert.isTrue(true, 'Should not throw exception for empty list');
    }
}