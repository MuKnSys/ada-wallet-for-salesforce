@isTest
private class UTXOControllerTest {
    private static final String TEST_PRIVATE_KEY = '0123456789abcdef0123456789abcdef';
    private static final String TEST_SEED_PHRASE = 'test seed phrase';
    
    @testSetup
    private static void testData() {
        AdaWalletsService.setPrivateKey(TEST_PRIVATE_KEY);

        Wallet_Set__c walletSet = new Wallet_Set__c(
            Wallet_Name__c = 'Test Wallet',
            Seed_Phrase__c = DataEncryptor.encrypt(TEST_SEED_PHRASE)
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

        Assert.areEqual(TEST_SEED_PHRASE, result, 'Decrypted seed phrase should match mock value');
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
    private static void testAddAddresses() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];

        // Test receiving address
        UTXOController.UTXOAddress receivingAddress = new UTXOController.UTXOAddress();
        receivingAddress.index = 0;
        receivingAddress.address = 'receivingAddress';
        receivingAddress.publicKey = 'publicKey';
        receivingAddress.paymentKeyHash = 'paymentKeyHash';
        receivingAddress.path = 'path';
        receivingAddress.privateKey = 'privateKey';
        
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
        
        // Test change address
        UTXOController.UTXOAddress changeAddress = new UTXOController.UTXOAddress();
        changeAddress.index = 0;
        changeAddress.address = 'changeAddress';
        changeAddress.publicKey = 'publicKey2';
        changeAddress.paymentKeyHash = 'paymentKeyHash2';
        changeAddress.path = 'path2';
        changeAddress.privateKey = 'privateKey2';
        
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
}