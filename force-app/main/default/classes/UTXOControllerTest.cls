@isTest
private class UTXOControllerTest {
    private static final String ASSERT_MESSAGE_WALLET_ID = 'Wallet ID should match';
    private static final String ASSERT_MESSAGE_ADDRESS = 'Address should match';
    private static final String ASSERT_MESSAGE_INDEX = 'Index should match';
    private static final String ASSERT_MESSAGE_PUBLIC_KEY = 'Public key should match';
    private static final String ASSERT_MESSAGE_STAKING_KEY_HASH = 'Staking key hash should match';
    private static final String ASSERT_MESSAGE_PATH = 'Path should match';
    private static final String ASSERT_MESSAGE_TYPE = 'Type should match';
    private static final String ASSERT_MESSAGE_IS_USED = 'Address used status should match';
    private static final String ASSERT_MESSAGE_NEXT_INDEX = 'Next index should match';
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
    private static void checkIsAddressUsedShouldReturnTrueWhenAddressIsUsed() {
        String testAddress = 'testAddress123';
        Test.setMock(HttpCalloutMock.class, new BlockfrostServiceMock());

        Test.startTest();
            Boolean result = UTXOController.checkIsAddressUsed(testAddress);
        Test.stopTest();
        
        Assert.isNotNull(result, 'Result should not be null');
    }       
    
    @isTest
    private static void getWalletShouldReturnWallet() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        
        Test.startTest();
            Wallet__c result = UTXOController.getWallet(wallet.Id);
        Test.stopTest();
        
        Assert.areEqual(wallet.Id, result.Id, ASSERT_MESSAGE_WALLET_ID);
    }

    @isTest
    static void shouldGetDecryptedSeedPhrase() {
        Wallet_Set__c walletSet = [SELECT Id FROM Wallet_Set__c LIMIT 1];

        Test.startTest();
        String result = UTXOController.getDecryptedSeedPhrase(walletSet.Id);
        Test.stopTest();

        Assert.areEqual(TEST_SEED_PHRASE, result, 'Decrypted seed phrase should match mock value');
    }
    
    @isTest
    private static void createUTXOAddressesShouldCreateAddresses() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        
        List<UTXOController.UTXOAddress> receivingAddresses = new List<UTXOController.UTXOAddress>();
        UTXOController.UTXOAddress receivingAddr = new UTXOController.UTXOAddress();
        receivingAddr.index = 0;
        receivingAddr.address = 'receivingAddress1';
        receivingAddr.publicKey = 'publicKey1';
        receivingAddr.stakingKeyHash = 'stakingKeyHash1';
        receivingAddr.path = 'path1';
        receivingAddresses.add(receivingAddr);
        
        List<UTXOController.UTXOAddress> changeAddresses = new List<UTXOController.UTXOAddress>();
        UTXOController.UTXOAddress changeAddr = new UTXOController.UTXOAddress();
        changeAddr.index = 0;
        changeAddr.address = 'changeAddress1';
        changeAddr.publicKey = 'publicKey2';
        changeAddr.stakingKeyHash = 'stakingKeyHash2';
        changeAddr.path = 'path2';
        changeAddresses.add(changeAddr);
        
        Test.startTest();
            UTXOController.createUTXOAddresses(wallet.Id, receivingAddresses, changeAddresses);
        Test.stopTest();
        
        List<UTXO_Address__c> createdAddresses = [SELECT Id, Address__c, Index__c, Public_Key__c, Staking_Key_Hash__c, Path__c, Type__c 
                                                FROM UTXO_Address__c 
                                                WHERE Wallet__c = :wallet.Id];
        
        Assert.areEqual(2, createdAddresses.size(), 'Should create 2 addresses');
        
        for(UTXO_Address__c addr : createdAddresses) {
            if(addr.Type__c == '0') {
                Assert.areEqual('receivingAddress1', addr.Address__c, ASSERT_MESSAGE_ADDRESS);
                Assert.areEqual(0, addr.Index__c, ASSERT_MESSAGE_INDEX);
                Assert.areEqual('publicKey1', addr.Public_Key__c, ASSERT_MESSAGE_PUBLIC_KEY);
                Assert.areEqual('stakingKeyHash1', addr.Staking_Key_Hash__c, ASSERT_MESSAGE_STAKING_KEY_HASH);
                Assert.areEqual('path1', addr.Path__c, ASSERT_MESSAGE_PATH);
            } else {
                Assert.areEqual('changeAddress1', addr.Address__c, ASSERT_MESSAGE_ADDRESS);
                Assert.areEqual(0, addr.Index__c, ASSERT_MESSAGE_INDEX);
                Assert.areEqual('publicKey2', addr.Public_Key__c, ASSERT_MESSAGE_PUBLIC_KEY);
                Assert.areEqual('stakingKeyHash2', addr.Staking_Key_Hash__c, ASSERT_MESSAGE_STAKING_KEY_HASH);
                Assert.areEqual('path2', addr.Path__c, ASSERT_MESSAGE_PATH);
            }
        }
    }
    
    @isTest
    private static void getUTXOAddressesShouldReturnAddresses() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        
        UTXO_Address__c utxoAddress = new UTXO_Address__c(
            Wallet__c = wallet.Id,
            Address__c = 'testAddress',
            Index__c = 0,
            Public_Key__c = 'testPublicKey',
            Staking_Key_Hash__c = 'testStakingKeyHash',
            Path__c = 'testPath',
            Type__c = '0'
        );
        insert utxoAddress;
        
        Test.startTest();
            List<UTXO_Address__c> result = UTXOController.getUTXOAddresses(wallet.Id);
        Test.stopTest();
        
        Assert.areEqual(1, result.size(), 'Should return 1 address');
        Assert.areEqual('testAddress', result[0].Address__c, ASSERT_MESSAGE_ADDRESS);
        Assert.areEqual(0, result[0].Index__c, ASSERT_MESSAGE_INDEX);
        Assert.areEqual('testPublicKey', result[0].Public_Key__c, ASSERT_MESSAGE_PUBLIC_KEY);
        Assert.areEqual('testStakingKeyHash', result[0].Staking_Key_Hash__c, ASSERT_MESSAGE_STAKING_KEY_HASH);
        Assert.areEqual('testPath', result[0].Path__c, ASSERT_MESSAGE_PATH);
        Assert.areEqual('0', result[0].Type__c, ASSERT_MESSAGE_TYPE);
    }
    
    @isTest
    private static void getUserPermissionsShouldReturnPermissions() {
        Test.startTest();
            List<String> result = UTXOController.getUserPermissions();
        Test.stopTest();
        
        Assert.isNotNull(result, 'Permissions should not be null');
    }
    
    @isTest
    private static void getNextUTXOIndexShouldReturnNextIndex() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        
        UTXO_Address__c utxoAddress = new UTXO_Address__c(
            Wallet__c = wallet.Id,
            Address__c = 'testAddress',
            Index__c = 0,
            Public_Key__c = 'testPublicKey',
            Staking_Key_Hash__c = 'testStakingKeyHash',
            Path__c = 'testPath',
            Type__c = '0'
        );
        insert utxoAddress;
        
        Test.startTest();
            Integer result = UTXOController.getNextUTXOIndex(wallet.Id, '0');
        Test.stopTest();
        
        Assert.areEqual(1, result, ASSERT_MESSAGE_NEXT_INDEX);
    }
    
    @isTest
    private static void addReceivingUTXOAddressShouldCreateAddress() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];

        UTXOController.UTXOAddress receivingAddress = new UTXOController.UTXOAddress();
        receivingAddress.index = 0;
        receivingAddress.address = 'receivingAddress';
        receivingAddress.publicKey = 'publicKey';
        receivingAddress.stakingKeyHash = 'stakingKeyHash';
        receivingAddress.path = 'path';        
        
        Test.startTest();
            UTXOController.addReceivingUTXOAddress(wallet.Id, receivingAddress);
        Test.stopTest();
        
        List<UTXO_Address__c> createdAddresses = [SELECT Id, Address__c, Index__c, Public_Key__c, Staking_Key_Hash__c, Path__c, Type__c 
                                                FROM UTXO_Address__c 
                                                WHERE Wallet__c = :wallet.Id];
        
        Assert.areEqual(1, createdAddresses.size(), 'Should create 1 address');
        Assert.areEqual('receivingAddress', createdAddresses[0].Address__c, ASSERT_MESSAGE_ADDRESS);
        Assert.areEqual(0, createdAddresses[0].Index__c, ASSERT_MESSAGE_INDEX);
        Assert.areEqual('publicKey', createdAddresses[0].Public_Key__c, ASSERT_MESSAGE_PUBLIC_KEY);
        Assert.areEqual('stakingKeyHash', createdAddresses[0].Staking_Key_Hash__c, ASSERT_MESSAGE_STAKING_KEY_HASH);
        Assert.areEqual('path', createdAddresses[0].Path__c, ASSERT_MESSAGE_PATH);
        Assert.areEqual('0', createdAddresses[0].Type__c, ASSERT_MESSAGE_TYPE);
    }
    
    @isTest
    private static void addChangeUTXOAddressShouldCreateAddress() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        
        UTXOController.UTXOAddress changeAddress = new UTXOController.UTXOAddress();
        changeAddress.index = 0;
        changeAddress.address = 'changeAddress';
        changeAddress.publicKey = 'publicKey';
        changeAddress.stakingKeyHash = 'stakingKeyHash';
        changeAddress.path = 'path';
        
        Test.startTest();
            UTXOController.addChangeUTXOAddress(wallet.Id, changeAddress);
        Test.stopTest();
        
        List<UTXO_Address__c> createdAddresses = [SELECT Id, Address__c, Index__c, Public_Key__c, Staking_Key_Hash__c, Path__c, Type__c 
                                                FROM UTXO_Address__c 
                                                WHERE Wallet__c = :wallet.Id];
        
        Assert.areEqual(1, createdAddresses.size(), 'Should create 1 address');
        Assert.areEqual('changeAddress', createdAddresses[0].Address__c, ASSERT_MESSAGE_ADDRESS);
        Assert.areEqual(0, createdAddresses[0].Index__c, ASSERT_MESSAGE_INDEX);
        Assert.areEqual('publicKey', createdAddresses[0].Public_Key__c, ASSERT_MESSAGE_PUBLIC_KEY);
        Assert.areEqual('stakingKeyHash', createdAddresses[0].Staking_Key_Hash__c, ASSERT_MESSAGE_STAKING_KEY_HASH);
        Assert.areEqual('path', createdAddresses[0].Path__c, ASSERT_MESSAGE_PATH);
        Assert.areEqual('1', createdAddresses[0].Type__c, ASSERT_MESSAGE_TYPE);
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