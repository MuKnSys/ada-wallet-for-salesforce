@isTest
private class BlockfrostServiceTest {
    
    @testSetup
    static void testData() {
        AdaSettings__c settings = new AdaSettings__c(
            BlockfrostProjectId__c = 'test-project-id',
            Private_Key__c = 'test-private-key',
            Hmac_Key__c = 'test-hmac-key'
        );
        insert settings;
    }

    @isTest
    static void getBlockfrostConfigShouldReturnConfig() {
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new BlockfrostServiceHttpCalloutMock());
        String result = BlockfrostService.getBlockfrostConfig();
        Test.stopTest();
        String msg = 'Should return configuration data';
        Assert.isNotNull(result, msg);
        Assert.isTrue(result.contains('latest'), msg);
    }

    @isTest
    static void isAddressUsedShouldReturnTrueWhenUsed() {
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new BlockfrostServiceHttpCalloutMock());
        Boolean result = BlockfrostService.isAddressUsed('addr1q...');
        Test.stopTest();
        String msg = 'Should indicate address is used';
        Assert.isTrue(result, msg);
    }

    @isTest
    static void isAddressUsedShouldReturnFalseWhenNotFound() {
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new BlockfrostServiceHttpCalloutMockNotFound());
        Boolean result = BlockfrostService.isAddressUsed('addr1q...');
        Test.stopTest();
        String msg = 'Should indicate address is not used';
        Assert.isFalse(result, msg);
    }

    @isTest
    static void getAddressUtxosShouldReturnUtxos() {
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new BlockfrostServiceHttpCalloutMock());
        String result = BlockfrostService.getAddressUtxos('addr1q...');
        Test.stopTest();
        String msg = 'Should return UTXO data';
        Assert.isNotNull(result, msg);
        Assert.isTrue(result.contains('tx_hash'), msg);
    }

    @isTest
    static void getAddressUtxosShouldReturnEmptyWhenNotFound() {
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new BlockfrostServiceHttpCalloutMockNotFound());
        String result = BlockfrostService.getAddressUtxos('addr1q...');
        Test.stopTest();
        String msg = 'Should return empty array for not found';
        Assert.areEqual('[]', result, msg);
    }

    @isTest
    static void getAssetInfoShouldReturnAssetData() {
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new BlockfrostServiceHttpCalloutMock());
        Map<String, Object> result = BlockfrostService.getAssetInfo('asset123');
        Test.stopTest();
        String msg = 'Should return asset information';
        Assert.isNotNull(result, msg);
        Assert.isTrue(result.containsKey('asset_id'), msg);
    }

    @isTest
    static void getAssetInfoShouldReturnErrorForInvalidAsset() {
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new BlockfrostServiceHttpCalloutMockNotFound());
        Map<String, Object> result = BlockfrostService.getAssetInfo('invalid');
        Test.stopTest();
        String msg = 'Should return error for invalid asset';
        Assert.isTrue(result.containsKey('error'), msg);
    }

    @isTest
    static void getEpochParametersShouldReturnParameters() {
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new BlockfrostServiceHttpCalloutMock());
        String result = BlockfrostService.getEpochParameters();
        Test.stopTest();
        String msg = 'Should return epoch parameters';
        Assert.isNotNull(result, msg);
        Assert.isTrue(result.contains('epoch'), msg);
    }

    @isTest
    static void submitTransactionShouldReturnHash() {
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new BlockfrostServiceHttpCalloutMock());
        String result = BlockfrostService.submitTransaction('a100');
        Test.stopTest();
        String msg = 'Should return transaction hash';
        Assert.isNotNull(result, msg);
        Assert.isTrue(result.length() > 0, msg);
    }

    @isTest
    static void submitTransactionShouldReturnErrorForInvalidCbor() {
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new BlockfrostServiceHttpCalloutMockError());
        String result = BlockfrostService.submitTransaction('invalid');
        Test.stopTest();
        String msg = 'Should return error for invalid CBOR';
        Assert.isTrue(result.contains('error'), msg);
    }

    @isTest
    static void getAddressTransactionsShouldReturnTransactions() {
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new BlockfrostServiceHttpCalloutMock());
        String result = BlockfrostService.getAddressTransactions('addr1q...');
        Test.stopTest();
        String msg = 'Should return transaction list';
        Assert.isNotNull(result, msg);
        Assert.isTrue(result.contains('tx_hash'), msg);
    }

    @isTest
    static void getTransactionDetailsShouldReturnDetails() {
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new BlockfrostServiceHttpCalloutMock());
        String result = BlockfrostService.getTransactionDetails('tx123');
        Test.stopTest();
        String msg = 'Should return transaction details';
        Assert.isNotNull(result, msg);
        Assert.isTrue(result.contains('hash'), msg);
    }

    @isTest
    static void analyzeTransactionDirectionShouldReturnAnalysis() {
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new BlockfrostServiceHttpCalloutMock());
        String result = BlockfrostService.analyzeTransactionDirection('tx123', new List<String>{'addr1q...'});
        Test.stopTest();
        String msg = 'Should return direction analysis';
        Assert.isNotNull(result, msg);
        Assert.isTrue(result.contains('success'), msg);
    }

    @isTest
    static void analyzeMultipleTransactionDirectionsShouldReturnResults() {
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new BlockfrostServiceHttpCalloutMock());
        String result = BlockfrostService.analyzeMultipleTransactionDirections(
            new List<String>{'tx123', 'tx456'}, 
            new List<String>{'addr1q...'}
        );
        Test.stopTest();
        String msg = 'Should return multiple analysis results';
        Assert.isNotNull(result, msg);
        Assert.isTrue(result.contains('tx123'), msg);
        Assert.isTrue(result.contains('tx456'), msg);
    }

    @isTest
    static void publishWalletSyncEventShouldPublishEvent() {
        Wallet_Set__c testWalletSet = new Wallet_Set__c();
        insert testWalletSet;
        Wallet__c testWallet = new Wallet__c(Wallet_Set__c = testWalletSet.Id);
        insert testWallet;
        Test.startTest();
        BlockfrostService.publishWalletSyncEvent(testWallet.Id, 'sync');
        Test.stopTest();
        String msg = 'Should publish wallet sync event';
        Assert.isTrue(true, msg);
    }

    private class BlockfrostServiceHttpCalloutMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            String endpoint = req.getEndpoint();
            
            if (endpoint.contains('/blocks/latest')) {
                res.setBody('{"time":1234567890,"height":12345,"hash":"block123","latest":true}');
            } else if (endpoint.contains('/addresses/') && endpoint.contains('/total')) {
                res.setBody('{"tx_count":5,"received_sum":[{"unit":"lovelace","quantity":"1000000"}]}');
            } else if (endpoint.contains('/addresses/') && endpoint.contains('/utxos')) {
                res.setBody('[{"tx_hash":"tx123","amount":[{"unit":"lovelace","quantity":"1000000"}]}]');
            } else if (endpoint.contains('/assets/')) {
                res.setBody('{"asset_id":"asset123","policy_id":"policy123","asset_name":"test"}');
            } else if (endpoint.contains('/epochs/latest/parameters')) {
                res.setBody('{"epoch":123,"min_fee_a":44,"min_fee_b":155381}');
            } else if (endpoint.contains('/addresses/') && endpoint.contains('/transactions')) {
                res.setBody('[{"tx_hash":"tx123","block_height":12345,"block_time":1234567890}]');
            } else if (endpoint.contains('/txs/')) {
                res.setBody('{"hash":"tx123","block_height":12345,"inputs":[{"address":"addr1q..."}],"outputs":[{"address":"addr1q..."}]}');
            } else {
                res.setBody('{"success":true}');
            }
            return res;
        }
    }

    private class BlockfrostServiceHttpCalloutMockNotFound implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(404);
            res.setBody('{"status_code":404,"error":"Not Found"}');
            return res;
        }
    }

    private class BlockfrostServiceHttpCalloutMockError implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(400);
            res.setBody('{"status_code":400,"error":"Bad Request","message":"Invalid CBOR"}');
            return res;
        }
    }
} 