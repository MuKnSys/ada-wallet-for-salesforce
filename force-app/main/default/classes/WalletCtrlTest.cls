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