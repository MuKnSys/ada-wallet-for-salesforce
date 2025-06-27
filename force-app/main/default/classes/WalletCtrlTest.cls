@isTest
private class WalletCtrlTest {
    private static final String ASSERT_MESSAGE_WALLET_ID = 'Wallet ID should match';
    private static final String ASSERT_MESSAGE_ADDRESS = 'Address should match';
    private static final String ASSERT_MESSAGE_TYPE = 'Type should match';
    private static final String ASSERT_MESSAGE_BALANCE = 'Balance should match';
    private static final String TEST_PRIVATE_KEY = '0123456789abcdef0123456789abcdef';
    private static final String TEST_SEED_PHRASE = 'test seed phrase';
    private static final String TEST_ADDRESS = 'testAddress123';
    private static final Decimal TEST_BALANCE = 1000000;
    
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
        
        UTXO_Address__c utxoAddress = new UTXO_Address__c(
            Wallet__c = wallet.Id,
            Address__c = TEST_ADDRESS,
            Index__c = 0,
            Public_Key__c = 'testPublicKey',
            Staking_Key_Hash__c = 'testStakingKeyHash',
            Path__c = 'testPath',
            Private_Key__c = 'testPrivateKey',
            Type__c = '0'
        );
        insert utxoAddress;
    }
    
    @isTest
    private static void getPaymentAddressShouldReturnUnusedAddress() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        Test.setMock(HttpCalloutMock.class, new BlockfrostServiceMock(0));
        
        Test.startTest();
            String result = WalletCtrl.getPaymentAddress(wallet.Id);
        Test.stopTest();
        
        Assert.areEqual(TEST_ADDRESS, result, ASSERT_MESSAGE_ADDRESS);
    }
    
    @isTest
    private static void getPaymentAddressShouldThrowExceptionWhenNoAddresses() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        delete [SELECT Id FROM UTXO_Address__c WHERE Wallet__c = :wallet.Id];
        Test.setMock(HttpCalloutMock.class, new BlockfrostServiceMock(0));
        
        Test.startTest();
            try {
                WalletCtrl.getPaymentAddress(wallet.Id);
                Assert.fail('Should throw an exception');
            } catch (Exception e) {
                Assert.isNotNull(e.getMessage(), 'Should throw an exception');
            }
        Test.stopTest();
    }
    
    @isTest
    private static void getPaymentAddressShouldThrowExceptionWhenAllAddressesUsed() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        Test.setMock(HttpCalloutMock.class, new BlockfrostServiceMock(2));
        
        Test.startTest();
            try {
                WalletCtrl.getPaymentAddress(wallet.Id);
                Assert.fail('Should throw an exception');
            } catch (Exception e) {
                Assert.isNotNull(e.getMessage(), 'Should throw an exception');
            }
        Test.stopTest();
    }
    
    @isTest
    private static void getWalletTotalBalanceShouldReturnBalance() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        Test.setMock(HttpCalloutMock.class, new BlockfrostServiceMock(0));
        
        Test.startTest();
            Map<String, Object> result = WalletCtrl.getWalletTotalBalance(wallet.Id);
        Test.stopTest();
        
        Map<String, Decimal> totalBalance = (Map<String, Decimal>) result.get('totalBalance');
        
        Assert.isNotNull(result, 'Balance should not be null');
        Assert.areEqual(TEST_BALANCE, totalBalance.get('lovelace'), ASSERT_MESSAGE_BALANCE);
    }

    private class BlockfrostServiceMock implements HttpCalloutMock {
        private Decimal txCount;
        
        public BlockfrostServiceMock(Decimal txCount) {
            this.txCount = txCount;
        }
        
        public HTTPResponse respond(HTTPRequest request) {
            HTTPResponse response = new HTTPResponse();
            response.setStatusCode(200);
                
            response.setBody('{"tx_count": ' + txCount + ',"received_sum": [{"unit": "lovelace", "quantity": "' + TEST_BALANCE + '"}], "sent_sum": [{"unit": "lovelace", "quantity": "0"}]}');                        
            return response;
        }
    }
} 