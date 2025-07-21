@IsTest
public with sharing class TransactionControllerTest {
    private static final String TEST_PRIVATE_KEY = EncodingUtil.base64Encode(Crypto.generateAesKey(256));
    private static final String TEST_HMAC_KEY = EncodingUtil.base64Encode(Crypto.generateAesKey(256));
    
    @TestSetup
    static void makeData() {
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
            Private_Key__c = DataEncryptor.encrypt('addr_xvk_test_private_key_1'),
            Public_Key__c = 'addr_xvk_test_public_key_1',
            Payment_Key_Hash__c = 'test_payment_key_hash_1'
        ));
        utxoAddresses.add(new UTXO_Address__c(
            Wallet__c = wallet.Id,
            Address__c = 'addr_test123456789_2',
            Index__c = 1,
            Path__c = 'm/44\'/1815\'/0\'/0/1',
            Type__c = '0',
            Private_Key__c = DataEncryptor.encrypt('addr_xvk_test_private_key_2'),
            Public_Key__c = 'addr_xvk_test_public_key_2',
            Payment_Key_Hash__c = 'test_payment_key_hash_2'
        ));
        utxoAddresses.add(new UTXO_Address__c(
            Wallet__c = wallet.Id,
            Address__c = 'addr_test_change_1',
            Index__c = 0,
            Path__c = 'm/44\'/1815\'/0\'/1/0',
            Type__c = '1',
            Private_Key__c = DataEncryptor.encrypt('addr_xvk_test_change_private_key_1'),
            Public_Key__c = 'addr_xvk_test_change_public_key_1',
            Payment_Key_Hash__c = 'test_change_payment_key_hash_1'
        ));
        utxoAddresses.add(new UTXO_Address__c(
            Wallet__c = wallet.Id,
            Address__c = 'addr_test_change_2',
            Index__c = 1,
            Path__c = 'm/44\'/1815\'/0\'/1/1',
            Type__c = '1',
            Private_Key__c = DataEncryptor.encrypt('addr_xvk_test_change_private_key_2'),
            Public_Key__c = 'addr_xvk_test_change_public_key_2',
            Payment_Key_Hash__c = 'test_change_payment_key_hash_2'
        ));
        insert utxoAddresses;
        List<UTXO_Asset__c> utxoAssets = new List<UTXO_Asset__c>();
        utxoAssets.add(new UTXO_Asset__c(
            UTXO_Address__c = utxoAddresses[0].Id,
            Asset__c = 'ADA',
            Amount__c = 1000000,
            Name__c = 'ADA',
            Decimals__c = 6
        ));
        utxoAssets.add(new UTXO_Asset__c(
            UTXO_Address__c = utxoAddresses[1].Id,
            Asset__c = 'f4364875e75320d405ceadebdf0db63fadaff55c72d4ff6b82f0676a434152474f',
            Amount__c = 5000000,
            Name__c = 'CARGO',
            Decimals__c = 6,
            Policy_ID__c = 'f4364875e75320d405ceadebdf0db63fadaff55c72d4ff6b82f0676a',
            Fingerprint__c = 'asset1234567890abcdef'
        ));
        utxoAssets.add(new UTXO_Asset__c(
            UTXO_Address__c = utxoAddresses[2].Id,
            Asset__c = 'ADA',
            Amount__c = 500000,
            Name__c = 'ADA',
            Decimals__c = 6
        ));
        utxoAssets.add(new UTXO_Asset__c(
            UTXO_Address__c = utxoAddresses[3].Id,
            Asset__c = 'f4364875e75320d405ceadebdf0db63fadaff55c72d4ff6b82f0676a434152474f',
            Amount__c = 2000000,
            Name__c = 'CARGO',
            Decimals__c = 6,
            Policy_ID__c = 'f4364875e75320d405ceadebdf0db63fadaff55c72d4ff6b82f0676a',
            Fingerprint__c = 'asset1234567890abcdef'
        ));
        insert utxoAssets;
    }
    
    @IsTest
    static void testLoadWalletWithValidId() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        
        Test.startTest();
            Test.setMock(HttpCalloutMock.class, new BlockfrostServiceHttpCalloutMock());
            Map<String, Object> result = TransactionController.loadWallet(wallet.Id);
        Test.stopTest();
        
        Assert.isNotNull(result, 'Should return wallet data');
        Assert.isTrue(result.containsKey('receivingAddresses'), 'Should contain receiving addresses');
        Assert.isTrue(result.containsKey('changeAddresses'), 'Should contain change addresses');
        Assert.isTrue(result.containsKey('walletSummary'), 'Should contain wallet summary');
    }
    
    @IsTest
    static void testLoadWalletWithInvalidId() {
        Test.startTest();
            Test.setMock(HttpCalloutMock.class, new BlockfrostServiceHttpCalloutMock());
            Map<String, Object> result = TransactionController.loadWallet('001000000000000');
        Test.stopTest();
        
        Assert.isNotNull(result, 'Should return wallet data for invalid wallet ID');
        Assert.isTrue(result.containsKey('receivingAddresses'), 'Should contain receiving addresses');
        Assert.isTrue(result.containsKey('changeAddresses'), 'Should contain change addresses');
        Assert.isTrue(result.containsKey('walletSummary'), 'Should contain wallet summary');
        Assert.areEqual(0, ((List<Object>)result.get('receivingAddresses')).size(), 'Should return empty receiving addresses for invalid wallet ID');
        Assert.areEqual(0, ((List<Object>)result.get('changeAddresses')).size(), 'Should return empty change addresses for invalid wallet ID');
    }
    
    @IsTest
    static void testLoadWalletWithNullId() {
        Test.startTest();
            Test.setMock(HttpCalloutMock.class, new BlockfrostServiceHttpCalloutMock());
            Map<String, Object> result = TransactionController.loadWallet(null);
        Test.stopTest();
        
        Assert.isNotNull(result, 'Should return wallet data for null wallet ID');
        Assert.isTrue(result.containsKey('receivingAddresses'), 'Should contain receiving addresses');
        Assert.isTrue(result.containsKey('changeAddresses'), 'Should contain change addresses');
        Assert.isTrue(result.containsKey('walletSummary'), 'Should contain wallet summary');
        Assert.areEqual(0, ((List<Object>)result.get('receivingAddresses')).size(), 'Should return empty receiving addresses for null wallet ID');
        Assert.areEqual(0, ((List<Object>)result.get('changeAddresses')).size(), 'Should return empty change addresses for null wallet ID');
    }
    
    @IsTest
    static void testGetEpochParameters() {
        Test.startTest();
            Test.setMock(HttpCalloutMock.class, new BlockfrostServiceHttpCalloutMock());
            String result = TransactionController.getEpochParameters();
        Test.stopTest();
        
        Assert.isNotNull(result, 'Should return epoch parameters');
    }
    
    @IsTest
    static void testGetTransactionLinesForOutboundWithValidId() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        Outbound_Transaction__c outboundTx = new Outbound_Transaction__c(
            Wallet__c = wallet.Id,
            To_Address__c = 'addr_test_recipient',
            Transaction_Status__c = 'Ready to Sign',
            Memo__c = 'Test transaction'
        );
        insert outboundTx;
        
        Outbound_Transaction_Line__c txLine = new Outbound_Transaction_Line__c(
            Outbound_Transaction__c = outboundTx.Id,
            Asset__c = 'ADA',
            Amount__c = 1000000
        );
        insert txLine;
        
        Test.startTest();
            List<Outbound_Transaction_Line__c> result = TransactionController.getTransactionLinesForOutbound(outboundTx.Id);
        Test.stopTest();
        
        Assert.isNotNull(result, 'Should return transaction lines');
        Assert.areEqual(1, result.size(), 'Should return one transaction line');
        Assert.areEqual(txLine.Id, result[0].Id, 'Should return correct transaction line');
    }
    
    @IsTest
    static void testGetTransactionLinesForOutboundWithInvalidId() {
        Test.startTest();
            List<Outbound_Transaction_Line__c> result = TransactionController.getTransactionLinesForOutbound('001000000000000');
        Test.stopTest();
        
        Assert.isNotNull(result, 'Should return empty list for invalid transaction ID');
        Assert.areEqual(0, result.size(), 'Should return empty list for invalid transaction ID');
    }
    
    @IsTest
    static void testGetOutboundTransactionWithValidId() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        Outbound_Transaction__c outboundTx = new Outbound_Transaction__c(
            Wallet__c = wallet.Id,
            To_Address__c = 'addr_test_recipient',
            Transaction_Status__c = 'Ready to Sign',
            Memo__c = 'Test transaction'
        );
        insert outboundTx;
        
        Test.startTest();
            Outbound_Transaction__c result = TransactionController.getOutboundTransaction(outboundTx.Id);
        Test.stopTest();
        
        Assert.isNotNull(result, 'Should return outbound transaction');
        Assert.areEqual(outboundTx.Id, result.Id, 'Should return correct transaction');
    }
    
    @IsTest
    static void testGetOutboundTransactionWithInvalidId() {
        Test.startTest();
            try {
                TransactionController.getOutboundTransaction('001000000000000');
                Assert.fail('Should throw exception for invalid transaction ID');
            } catch (AuraHandledException e) {
                Assert.isNotNull(e.getMessage(), 'Should throw exception with message');
            }
        Test.stopTest();
    }
    
    @IsTest
    static void testUpdateOutboundTransactionWithSignedCborWithValidData() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        Outbound_Transaction__c outboundTx = new Outbound_Transaction__c(
            Wallet__c = wallet.Id,
            To_Address__c = 'addr_test_recipient',
            Transaction_Status__c = 'Ready to Sign',
            Memo__c = 'Test transaction'
        );
        insert outboundTx;
        
        String signedCbor = 'test_signed_cbor_data';
        
        Test.startTest();
            TransactionController.updateOutboundTransactionWithSignedCbor(outboundTx.Id, signedCbor);
        Test.stopTest();
        
        Outbound_Transaction__c updatedTx = [SELECT Id, Signed_Transaction_CBOR__c, Transaction_Status__c 
                                           FROM Outbound_Transaction__c WHERE Id = :outboundTx.Id];
        Assert.areEqual(signedCbor, updatedTx.Signed_Transaction_CBOR__c, 'Should update signed CBOR');
        Assert.areEqual('Ready to Send', updatedTx.Transaction_Status__c, 'Should update status');
    }
    
    @IsTest
    static void testUpdateOutboundTransactionWithSignedCborWithNullRecordId() {
        Test.startTest();
            try {
                TransactionController.updateOutboundTransactionWithSignedCbor(null, 'test_cbor');
                Assert.fail('Should throw exception for null record ID');
            } catch (AuraHandledException e) {
                Assert.isNotNull(e.getMessage(), 'Should throw exception with message');
            }
        Test.stopTest();
    }
    
    @IsTest
    static void testUpdateOutboundTransactionWithSignedCborWithNullCbor() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        Outbound_Transaction__c outboundTx = new Outbound_Transaction__c(
            Wallet__c = wallet.Id,
            To_Address__c = 'addr_test_recipient',
            Transaction_Status__c = 'Ready to Sign',
            Memo__c = 'Test transaction'
        );
        insert outboundTx;
        
        Test.startTest();
            try {
                TransactionController.updateOutboundTransactionWithSignedCbor(outboundTx.Id, null);
                Assert.fail('Should throw exception for null CBOR');
            } catch (AuraHandledException e) {
                Assert.isNotNull(e.getMessage(), 'Should throw exception with message');
            }
        Test.stopTest();
    }
    
    @IsTest
    static void testUpdateOutboundTransactionWithSignedCborWithInvalidRecordId() {
        Test.startTest();
            try {
                TransactionController.updateOutboundTransactionWithSignedCbor('001000000000000', 'test_cbor');
                Assert.fail('Should throw exception for invalid record ID');
            } catch (AuraHandledException e) {
                Assert.isNotNull(e.getMessage(), 'Should throw exception with message');
            }
        Test.stopTest();
    }
    
    @IsTest
    static void testCalculateLovelaceFromUtxosDirect() {
        List<Object> utxos = new List<Object>{
            new Map<String, Object>{
                'amount' => new List<Object>{
                    new Map<String, Object>{'unit' => 'lovelace', 'quantity' => '100'},
                    new Map<String, Object>{'unit' => 'lovelace', 'quantity' => '200'}
                }
            },
            new Map<String, Object>{
                'amount' => new List<Object>{
                    new Map<String, Object>{'unit' => 'lovelace', 'quantity' => '300'}
                }
            }
        };
        Decimal result = TransactionController.calculateLovelaceFromUtxos(utxos);
        Assert.areEqual(600, result, 'Should sum all lovelace quantities');
    }

    @IsTest
    static void testCollectAssetTotalsDirect() {
        List<Object> utxos = new List<Object>{
            new Map<String, Object>{
                'amount' => new List<Object>{
                    new Map<String, Object>{'unit' => 'token1', 'quantity' => '10'},
                    new Map<String, Object>{'unit' => 'token2', 'quantity' => '20'}
                }
            },
            new Map<String, Object>{
                'amount' => new List<Object>{
                    new Map<String, Object>{'unit' => 'token1', 'quantity' => '30'}
                }
            }
        };
        Map<String, Decimal> assetTotals = new Map<String, Decimal>();
        TransactionController.collectAssetTotals(utxos, assetTotals);
        Assert.areEqual(40, assetTotals.get('token1'), 'Should sum token1 quantities');
        Assert.areEqual(20, assetTotals.get('token2'), 'Should sum token2 quantities');
    }

    @IsTest
    static void testBuildAssetsListDirect() {
        Map<String, Decimal> assetTotals = new Map<String, Decimal>{
            'token1' => 10,
            'token2' => 20
        };
        List<Map<String, Object>> assetsList = TransactionController.buildAssetsList(assetTotals);
        Assert.areEqual(2, assetsList.size(), 'Should build list for each asset');
    }

    @IsTest
    static void testCreateAssetObjectDirect() {
        Map<String, Object> assetObj = TransactionController.createAssetObject('lovelace', 100);
        Assert.isTrue(assetObj.containsKey('unit'), 'Should contain unit');
        Assert.areEqual('lovelace', assetObj.get('unit'), 'Unit should be lovelace');
        Assert.areEqual('100', assetObj.get('quantity'), 'Quantity should be string value');
    }

    @IsTest
    static void testPopulateAssetMetadataDirect() {
        Map<String, Object> assetObj = new Map<String, Object>();
        Map<String, Object> assetInfo = new Map<String, Object>{
            'policy_id' => 'pid',
            'asset_name' => 'aname',
            'fingerprint' => 'fp',
            'metadata' => new Map<String, Object>{
                'decimals' => 2,
                'ticker' => 'TICK',
                'description' => 'desc'
            }
        };
        TransactionController.populateAssetMetadata(assetObj, assetInfo);
        Assert.areEqual('pid', assetObj.get('policyId'), 'Should set policyId');
        Assert.areEqual('aname', assetObj.get('assetName'), 'Should set assetName');
        Assert.areEqual('fp', assetObj.get('fingerprint'), 'Should set fingerprint');
        Assert.areEqual(2, assetObj.get('decimals'), 'Should set decimals');
        Assert.areEqual('TICK', assetObj.get('ticker'), 'Should set ticker');
        Assert.areEqual('desc', assetObj.get('description'), 'Should set description');
    }

    @IsTest
    static void testPopulateMetadataFieldsDirect() {
        Map<String, Object> assetObj = new Map<String, Object>{'assetName' => 'aname'};
        Map<String, Object> metadata = new Map<String, Object>{
            'decimals' => 3,
            'ticker' => 'TICK2',
            'description' => 'desc2'
        };
        TransactionController.populateMetadataFields(assetObj, metadata);
        Assert.areEqual(3, assetObj.get('decimals'), 'Should set decimals');
        Assert.areEqual('TICK2', assetObj.get('ticker'), 'Should set ticker');
        Assert.areEqual('desc2', assetObj.get('description'), 'Should set description');
    }

    @IsTest
    static void testPopulateDefaultMetadataDirect() {
        Map<String, Object> assetObj = new Map<String, Object>{'assetName' => 'aname'};
        TransactionController.populateDefaultMetadata(assetObj);
        Assert.areEqual(0, assetObj.get('decimals'), 'Should set decimals to 0');
        Assert.areEqual('aname', assetObj.get('ticker'), 'Should set ticker to assetName');
        Assert.areEqual('', assetObj.get('description'), 'Should set description to empty');
    }

    @IsTest
    static void testPopulateFallbackAssetMetadataDirect() {
        Map<String, Object> assetObj = new Map<String, Object>();
        String unit = '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdefextra';
        TransactionController.populateFallbackAssetMetadata(assetObj, unit);
        Assert.isTrue(assetObj.containsKey('policyId'), 'Should set policyId');
        Assert.isTrue(assetObj.containsKey('assetName'), 'Should set assetName');
        Assert.isTrue(assetObj.containsKey('fingerprint'), 'Should set fingerprint');
        Assert.isTrue(assetObj.containsKey('decimals'), 'Should set decimals');
        Assert.isTrue(assetObj.containsKey('ticker'), 'Should set ticker');
        Assert.isTrue(assetObj.containsKey('description'), 'Should set description');
    }

    @IsTest
    static void testGetStringValueDirect() {
        Map<String, Object> dataMap = new Map<String, Object>{'key1' => 'val1'};
        String val = TransactionController.getStringValue(dataMap, 'key1', 'default');
        Assert.areEqual('val1', val, 'Should return value from map');
        String def = TransactionController.getStringValue(dataMap, 'key2', 'default');
        Assert.areEqual('default', def, 'Should return default if key not found');
    }
} 