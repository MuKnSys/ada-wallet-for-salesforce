@IsTest
public with sharing class UTXOHelperTest {
    private static final String TEST_PRIVATE_KEY = EncodingUtil.base64Encode(Crypto.generateAesKey(256));
    private static final String TEST_HMAC_KEY = EncodingUtil.base64Encode(Crypto.generateAesKey(256));

    @TestSetup
    static void testData() {
        AdaWalletsService.setPrivateKey(TEST_PRIVATE_KEY);
        AdaWalletsService.setHmacKey(TEST_HMAC_KEY);

        Wallet_Set__c walletSet = new Wallet_Set__c(
            Wallet_Name__c = 'Test Wallet Set',
            Seed_Phrase__c = DataEncryptor.encryptHmac('test seed phrase for unit testing purposes only')
        );
        insert walletSet;
        
        Wallet__c wallet = new Wallet__c(
            Wallet_Set__c = walletSet.Id,
            Account_Index__c = 0
        );
        insert wallet;
        
        List<UTXO_Address__c> utxoAddresses = new List<UTXO_Address__c>();
        utxoAddresses.add(new UTXO_Address__c(
            Wallet__c = wallet.Id,
            Address__c = 'addr_test123456789_1',
            Index__c = 0,
            Path__c = 'm/44\'/1815\'/0\'/0/0',
            Type__c = '0',
            Private_Key__c = 'addr_xvk_test_private_key_1',
            Public_Key__c = 'addr_xvk_test_public_key_1',
            Payment_Key_Hash__c = 'test_payment_key_hash_1',
            Is_Used__c = false
        ));
        utxoAddresses.add(new UTXO_Address__c(
            Wallet__c = wallet.Id,
            Address__c = 'addr_test123456789_2',
            Index__c = 1,
            Path__c = 'm/44\'/1815\'/0\'/0/1',
            Type__c = '0',
            Private_Key__c = 'addr_xvk_test_private_key_2',
            Public_Key__c = 'addr_xvk_test_public_key_2',
            Payment_Key_Hash__c = 'test_payment_key_hash_2',
            Is_Used__c = true
        ));
        insert utxoAddresses;
    }

    private class BlockfrostServiceHttpCalloutMockRealistic implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            String endpoint = req.getEndpoint();
            
            if (endpoint.contains('addresses/') && endpoint.contains('/utxos')) {
                res.setBody('[' +
                    '{"tx_hash":"txhash1","amount":[' +
                        '{"unit":"lovelace","quantity":"1500000"},' +
                        '{"unit":"a0ff2d0014332e0b334199a027d60aa7ad89827e869292c7fc4dc0f3.TKN1","quantity":"100"},' +
                        '{"unit":"b1ff2d0014332e0b334199a027d60aa7ad89827e869292c7fc4dc0f3.TKN2","quantity":"200"}' +
                    ']}' +
                ']');
            } else if (endpoint.contains('addresses/') && endpoint.contains('/transactions')) {
                res.setBody('[' +
                    '{"tx_hash":"txhash1","block_height":12345,"block_time":1234567890,"tx_index":0},' +
                    '{"tx_hash":"txhash2","block_height":12346,"block_time":1234567891,"tx_index":1}' +
                ']');
            } else if (endpoint.contains('txs/') && !endpoint.contains('/utxos')) {
                String txHash = endpoint.substring(endpoint.lastIndexOf('/') + 1);
                if (txHash == 'txhash1') {
                    res.setBody('{"hash":"txhash1","block_height":12345,"block_time":1234567890,"tx_index":0,"inputs":[{"address":"addr_test123456789_3"}],"outputs":[{"address":"addr_test123456789_1"}]}');
                } else if (txHash == 'txhash2') {
                    res.setBody('{"hash":"txhash2","block_height":12346,"block_time":1234567891,"tx_index":1,"inputs":[{"address":"addr_test123456789_1"}],"outputs":[{"address":"addr_test123456789_4"}]}');
                } else {
                    res.setBody('{}');
                }
            } else if (endpoint.contains('txs/') && endpoint.contains('/utxos')) {
                String txHash = endpoint.substring(endpoint.lastIndexOf('/') + 1);
                if (txHash == 'txhash1') {
                    res.setBody('{"hash":"txhash1","inputs":[{"address":"addr_test123456789_3"}],"outputs":[{"address":"addr_test123456789_1"}]}');
                } else if (txHash == 'txhash2') {
                    res.setBody('{"hash":"txhash2","inputs":[{"address":"addr_test123456789_1"}],"outputs":[{"address":"addr_test123456789_4"}]}');
                } else {
                    res.setBody('{}');
                }
            } else if (endpoint.contains('assets/')) {
                String assetId = endpoint.substring(endpoint.lastIndexOf('/') + 1);
                if (assetId.contains('TKN1')) {
                    res.setBody('{"policy_id":"a0ff2d0014332e0b334199a027d60aa7ad89827e869292c7fc4dc0f3","fingerprint":"asset1xyz","metadata":{"ticker":"TKN1","name":"Token One","decimals":6,"logo":"data:image/png;base64,xyz"}}');
                } else if (assetId.contains('TKN2')) {
                    res.setBody('{"policy_id":"b1ff2d0014332e0b334199a027d60aa7ad89827e869292c7fc4dc0f3","fingerprint":"asset2xyz","metadata":{"ticker":"TKN2","name":"Token Two","decimals":0}}');
                } else {
                    res.setBody('{}');
                }
            } else if (endpoint.contains('analyzeMultipleTransactionDirections')) {
                // This branch is not used in current implementation but retained for completeness
                res.setBody('{"txhash1":{"success":true,"isOutbound":false},"txhash2":{"success":true,"isOutbound":true}}');
            } else {
                res.setBody('{}');
            }
            return res;
        }
    }

    private class BlockfrostServiceHttpCalloutMockEmpty implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('[]');
            return res;
        }
    }

    private class BlockfrostServiceHttpCalloutMockError implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(404);
            res.setBody('{"status_code":404,"error":"Not Found"}');
            return res;
        }
    }

    @IsTest
    static void testSyncAssetsAndTransactionsFullFlow() {
        PermissionSet paymentPs = [SELECT Id FROM PermissionSet WHERE Name = 'Ada_Wallet_Payment' LIMIT 1];
        User currentUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        System.runAs(currentUser) {
            insert new PermissionSetAssignment(
                AssigneeId = currentUser.Id,
                PermissionSetId = paymentPs.Id
            );
        }

        UTXO_Address__c utxoAddress = [
            SELECT Id, Address__c, Wallet__c, Is_Used__c 
            FROM UTXO_Address__c 
            WHERE Is_Used__c = false 
            LIMIT 1
        ];

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new BlockfrostServiceHttpCalloutMockRealistic());
        Map<String, Object> result = new Map<String, Object> ();
        System.runAs(currentUser) {
            result = UTXOHelper.syncAssetsAndTransactions(utxoAddress.Id);
        }
        Test.stopTest();

        // Verify result structure
        Assert.isTrue((Boolean)result.get('success'), 'Should indicate success');
        Assert.isNotNull(result.get('assets'), 'Should contain assets data');
        Assert.isNotNull(result.get('transactions'), 'Should contain transactions data');
        Assert.isNotNull(result.get('statistics'), 'Should contain statistics');

        // Verify assets were created
        List<UTXO_Asset__c> assets = [
            SELECT Id, Asset__c, Amount__c, Name__c, Decimals__c, Policy_ID__c, Fingerprint__c, Icon__c 
            FROM UTXO_Asset__c 
            WHERE UTXO_Address__c = :utxoAddress.Id
            ORDER BY Asset__c
        ];
        Assert.areEqual(3, assets.size(), 'Should create 3 assets (ADA + 2 tokens)');
        
        // Verify ADA asset
        UTXO_Asset__c ada = assets[0];
        Assert.areEqual('ADA', ada.Asset__c, 'Should set ADA asset name');
        Assert.areEqual(1500000, ada.Amount__c, 'Should sum up ADA amounts');
        Assert.areEqual(6, ada.Decimals__c, 'Should set ADA decimals to 6');
        
        // Verify TKN1
        UTXO_Asset__c tkn1 = assets[1];
        Assert.areEqual('TKN1', tkn1.Asset__c, 'Should set token1 symbol');
        Assert.areEqual(100, tkn1.Amount__c, 'Should set token1 amount');
        Assert.areEqual('Token One', tkn1.Name__c, 'Should set token1 name');
        Assert.areEqual(6, tkn1.Decimals__c, 'Should set token1 decimals');
        Assert.areEqual('a0ff2d0014332e0b334199a027d60aa7ad89827e869292c7fc4dc0f3', tkn1.Policy_ID__c, 'Should set token1 policy ID');
        Assert.areEqual('asset1xyz', tkn1.Fingerprint__c, 'Should set token1 fingerprint');
        Assert.isTrue(tkn1.Icon__c.startsWith('data:image/png;base64,'), 'Should set token1 icon');
        
        // Verify TKN2
        UTXO_Asset__c tkn2 = assets[2];
        Assert.areEqual('TKN2', tkn2.Asset__c, 'Should set token2 symbol');
        Assert.areEqual(200, tkn2.Amount__c, 'Should set token2 amount');
        Assert.areEqual('Token Two', tkn2.Name__c, 'Should set token2 name');
        Assert.areEqual(0, tkn2.Decimals__c, 'Should set token2 decimals');
        Assert.areEqual('b1ff2d0014332e0b334199a027d60aa7ad89827e869292c7fc4dc0f3', tkn2.Policy_ID__c, 'Should set token2 policy ID');
        Assert.areEqual('asset2xyz', tkn2.Fingerprint__c, 'Should set token2 fingerprint');
        Assert.areEqual('utility:money', tkn2.Icon__c, 'Should set default icon when none provided');
        
        // Verify transactions
        List<Inbound_Transaction__c> inboundTxs = [
            SELECT Transaction_Hash__c, Block_Height__c, Block_Time__c, Transaction_Index__c
            FROM Inbound_Transaction__c 
            WHERE UTXO_Address__c = :utxoAddress.Id
            ORDER BY Block_Height__c
        ];
        Assert.areEqual(2, inboundTxs.size(), 'Should create 2 Inbound_Transaction__c records (all transactions are saved)');
        
        // Verify first transaction
        Inbound_Transaction__c tx1 = inboundTxs[0];
        Assert.areEqual('txhash1', tx1.Transaction_Hash__c, 'Should set tx1 hash');
        Assert.areEqual(12345, tx1.Block_Height__c, 'Should set tx1 block height');
        Assert.areEqual(1234567890, tx1.Block_Time__c, 'Should set tx1 block time');
        Assert.areEqual(0, tx1.Transaction_Index__c, 'Should set tx1 index');
        
        // Verify UTXO address was marked as used
        UTXO_Address__c updatedAddr = [SELECT Is_Used__c FROM UTXO_Address__c WHERE Id = :utxoAddress.Id];
        Assert.isTrue(updatedAddr.Is_Used__c, 'Should mark address as used');
        
        // Verify statistics
        Map<String, Object> stats = (Map<String, Object>)result.get('statistics');
        Assert.areEqual(3, (Integer)stats.get('assetsInserted'), 'Should report 3 assets inserted');
        Assert.areEqual(1, (Integer)stats.get('inboundTransactionsFound'), 'Should report 1 inbound transaction');
        Assert.areEqual(1, (Integer)stats.get('outboundTransactionsFound'), 'Should report 1 outbound transaction');
        Assert.areEqual(2, (Integer)stats.get('totalTransactionsFound'), 'Should report 2 total transactions');
    }

    @IsTest
    static void testSetAddressesUsed() {
        List<UTXO_Address__c> addresses = [
            SELECT Id, Address__c, Wallet__c, Is_Used__c 
            FROM UTXO_Address__c
        ];
        List<Id> addressIds = new List<Id>();
        for (UTXO_Address__c addr : addresses) {
            addr.Is_Used__c = false;
            addressIds.add(addr.Id);
        }
        update addresses;
        
        Test.startTest();
        UTXOHelper.setAddressesUsed(addressIds);
        Test.stopTest();
        
        List<UTXO_Address__c> updatedAddresses = [SELECT Id, Is_Used__c FROM UTXO_Address__c WHERE Id IN :addressIds];
        for (UTXO_Address__c addr : updatedAddresses) {
            Assert.isTrue(addr.Is_Used__c, 'Should mark all addresses as used');
        }
    }
} 