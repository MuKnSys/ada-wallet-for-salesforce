@IsTest
public with sharing class WalletControllerTest {
    private static final String TEST_PRIVATE_KEY = EncodingUtil.base64Encode(Crypto.generateAesKey(256));
    private static final String TEST_HMAC_KEY = EncodingUtil.base64Encode(Crypto.generateAesKey(256));
    private static final String ERROR_WALLET_ID_NULL = 'Wallet ID cannot be null';
    private static final String ERROR_TO_ADDRESS_REQUIRED = 'To Address is required';
    private static final String ERROR_ASSETS_REQUIRED = 'At least one asset is required';
    private static final String ERROR_AMOUNT_REQUIRED = 'Amount is required';
    private static final String ERROR_ASSET_REQUIRED = 'Asset is required';
    private static final String ERROR_INVALID_AMOUNT = 'Invalid amount format';
    private static final String ERROR_AMOUNT_MUST_BE_POSITIVE = 'Amount must be greater than 0';
    
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

        List<UTXO_Asset__c> utxoAssets = new List<UTXO_Asset__c>();
        utxoAssets.add(new UTXO_Asset__c(
            UTXO_Address__c = utxoAddresses[0].Id,
            Asset__c = 'ADA',
            Amount__c = 1000000,
            Name__c = 'ADA',
            Decimals__c = 6,
            Icon__c = 'utility:money'
        ));
        utxoAssets.add(new UTXO_Asset__c(
            UTXO_Address__c = utxoAddresses[0].Id,
            Asset__c = 'f4364875e75320d405ceadebdf0db63fadaff55c72d4ff6b82f0676a434152474f',
            Amount__c = 5000000,
            Name__c = 'CARGO',
            Decimals__c = 6,
            Policy_ID__c = 'f4364875e75320d405ceadebdf0db63fadaff55c72d4ff6b82f0676a',
            Fingerprint__c = 'asset1234567890abcdef',
            Icon__c = 'utility:money'
        ));
        utxoAssets.add(new UTXO_Asset__c(
            UTXO_Address__c = utxoAddresses[1].Id,
            Asset__c = 'ADA',
            Amount__c = 500000,
            Name__c = 'ADA',
            Decimals__c = 6,
            Icon__c = 'utility:money'
        ));
        insert utxoAssets;
        
        List<Inbound_Transaction__c> inboundTxs = new List<Inbound_Transaction__c>();
        inboundTxs.add(new Inbound_Transaction__c(
            UTXO_Address__c = utxoAddresses[0].Id,
            Transaction_Hash__c = 'tx_hash_inbound_1',
            Block_Height__c = 12345,
            Block_Time__c = 1234567890
        ));
        insert inboundTxs;
        
        List<Outbound_Transaction__c> outboundTxs = new List<Outbound_Transaction__c>();
        outboundTxs.add(new Outbound_Transaction__c(
            Wallet__c = wallet.Id,
            To_Address__c = 'addr_test_recipient',
            Transaction_Status__c = ConstantsAda.STATUS_READY_TO_SIGN,
            Memo__c = 'Test outbound transaction'
        ));
        insert outboundTxs;
        
        List<Outbound_Transaction_Line__c> txLines = new List<Outbound_Transaction_Line__c>();
        txLines.add(new Outbound_Transaction_Line__c(
            Outbound_Transaction__c = outboundTxs[0].Id,
            Asset__c = 'ADA',
            Amount__c = 100000
        ));
        insert txLines;
    }
    
    @IsTest
    static void getWalletAssetSummaryShouldReturnAssetSummaryWhenWalletHasAssets() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        
        Test.startTest();
            Map<String, Object> result = WalletController.getWalletAssetSummary(wallet.Id);
        Test.stopTest();
        
        Assert.isNotNull(result, 'Should return asset summary');
        Assert.isTrue((Boolean)result.get('success'), 'Should indicate success');
        Assert.isNotNull(result.get('adaBalance'), 'Should contain ADA balance');
        Assert.isNotNull(result.get('tokens'), 'Should contain tokens list');
        Assert.isNotNull(result.get('totalAssets'), 'Should contain total assets count');
        Assert.isNotNull(result.get('message'), 'Should contain message');
    }
    
    @IsTest
    static void getWalletAssetSummaryShouldReturnEmptySummaryWhenWalletHasNoAddresses() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        
        delete [SELECT Id FROM UTXO_Address__c WHERE Wallet__c = :wallet.Id];
        
        Test.startTest();
            Map<String, Object> result = WalletController.getWalletAssetSummary(wallet.Id);
        Test.stopTest();
        
        Assert.isNotNull(result, 'Should return empty asset summary');
        Assert.isTrue((Boolean)result.get('success'), 'Should indicate success');
        Assert.areEqual(0, (Decimal)result.get('adaBalance'), 'Should have zero ADA balance');
        Assert.areEqual(0, ((List<Object>)result.get('tokens')).size(), 'Should have empty tokens list');
        Assert.areEqual(0, (Integer)result.get('totalAssets'), 'Should have zero total assets');
    }
    
    @IsTest
    static void getWalletAssetSummaryShouldThrowExceptionWhenWalletIdIsNull() {
        Test.startTest();
            try {
                WalletController.getWalletAssetSummary(null);
                Assert.fail('Should throw exception for null wallet ID');
            } catch (AuraHandledException e) {
                Assert.isNotNull(e.getMessage(), 'Should throw exception with message');
            }
        Test.stopTest();
    }
    
    @IsTest
    static void fetchWalletTransactionsShouldReturnTransactionsWhenWalletHasTransactions() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        
        Test.startTest();
            Map<String, Object> result = WalletController.fetchWalletTransactions(wallet.Id);
        Test.stopTest();
        
        Assert.isNotNull(result, 'Should return transaction data');
        Assert.isTrue((Boolean)result.get('success'), 'Should indicate success');
        Assert.isNotNull(result.get('inbound'), 'Should contain inbound transactions');
        Assert.isNotNull(result.get('outbound'), 'Should contain outbound transactions');
        Assert.isNotNull(result.get('totalInbound'), 'Should contain total inbound count');
        Assert.isNotNull(result.get('totalOutbound'), 'Should contain total outbound count');
        Assert.isNotNull(result.get('message'), 'Should contain message');
    }
    
    @IsTest
    static void fetchWalletTransactionsShouldReturnEmptyListsWhenWalletHasNoTransactions() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        
        delete [SELECT Id FROM Inbound_Transaction__c];
        delete [SELECT Id FROM Outbound_Transaction__c];
        
        Test.startTest();
            Map<String, Object> result = WalletController.fetchWalletTransactions(wallet.Id);
        Test.stopTest();
        
        Assert.isNotNull(result, 'Should return transaction data');
        Assert.isTrue((Boolean)result.get('success'), 'Should indicate success');
        Assert.areEqual(0, (Integer)result.get('totalInbound'), 'Should have zero inbound transactions');
        Assert.areEqual(0, (Integer)result.get('totalOutbound'), 'Should have zero outbound transactions');
    }
    
    @IsTest
    static void fetchWalletTransactionsShouldThrowExceptionWhenWalletIdIsNull() {
        Test.startTest();
            try {
                WalletController.fetchWalletTransactions(null);
                Assert.fail('Should throw exception for null wallet ID');
            } catch (AuraHandledException e) {
                Assert.isNotNull(e.getMessage(), 'Should throw exception with message');
            }
        Test.stopTest();
    }
    
    @IsTest
    static void syncAssetsAndTransactionsShouldReturnResultWhenUtxoAddressIdIsValid() {
        UTXO_Address__c utxoAddress = [SELECT Id FROM UTXO_Address__c LIMIT 1];
        
        Test.startTest();
            Map<String, Object> result = WalletController.syncAssetsAndTransactions(utxoAddress.Id);
        Test.stopTest();
        
        Assert.isNotNull(result, 'Should return sync result');
    }
    
    @IsTest
    static void getAllWalletAddressesShouldReturnAddressesWhenWalletHasAddresses() {
        PermissionSet paymentPs = [SELECT Id FROM PermissionSet WHERE Name = 'Ada_Wallet_Payment' LIMIT 1];
        User currentUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        System.runAs(currentUser) {
            insert new PermissionSetAssignment(
                AssigneeId = currentUser.Id,
                PermissionSetId = paymentPs.Id
            );
        }
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        List<UTXO_Address__c> result = new List<UTXO_Address__c> ();

        Test.startTest();
            System.runAs(currentUser) {
                result = WalletController.getAllWalletAddresses(wallet.Id);
            }
        Test.stopTest();

        Assert.isNotNull(result, 'Should return wallet addresses');
        Assert.areEqual(2, result.size(), 'Should return correct number of addresses');
    }

    @IsTest
    static void getAllWalletAddressesShouldReturnEmptyListWhenWalletHasNoAddresses() {
        PermissionSet paymentPs = [SELECT Id FROM PermissionSet WHERE Name = 'Ada_Wallet_Payment' LIMIT 1];
        User currentUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        System.runAs(currentUser) {
            insert new PermissionSetAssignment(
                AssigneeId = currentUser.Id,
                PermissionSetId = paymentPs.Id
            );
        }
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];

        delete [SELECT Id FROM UTXO_Address__c WHERE Wallet__c = :wallet.Id];
        List<UTXO_Address__c> result = new List<UTXO_Address__c> ();

        Test.startTest();
            System.runAs(currentUser) {
                result = WalletController.getAllWalletAddresses(wallet.Id);
            }
        Test.stopTest();

        Assert.isNotNull(result, 'Should return empty list');
        Assert.areEqual(0, result.size(), 'Should return empty list when no addresses exist');
    }

    @IsTest
    static void getFirstUnusedReceivingAddressShouldReturnAddressWhenUnusedAddressExists() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        
        Test.startTest();
            String result = WalletController.getFirstUnusedReceivingAddress(wallet.Id);
        Test.stopTest();
        
        Assert.isNotNull(result, 'Should return unused receiving address');
        Assert.areEqual('addr_test123456789_1', result, 'Should return correct unused address');
    }
    
    @IsTest
    static void getFirstUnusedReceivingAddressShouldReturnNullWhenNoUnusedAddressExists() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        
        List<UTXO_Address__c> addresses = [SELECT Id FROM UTXO_Address__c WHERE Wallet__c = :wallet.Id];
        for (UTXO_Address__c addr : addresses) {
            addr.Is_Used__c = true;
        }
        update addresses;
        
        Test.startTest();
            String result = WalletController.getFirstUnusedReceivingAddress(wallet.Id);
        Test.stopTest();
        
        Assert.isNull(result, 'Should return null when no unused address exists');
    }
    
    @IsTest
    static void createMultiAssetOutboundTransactionShouldCreateTransactionWhenValidInput() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        String toAddress = 'addr_test_recipient';
        List<Map<String, Object>> assets = new List<Map<String, Object>>{
            new Map<String, Object>{
                'asset' => 'ADA',
                'amount' => '1000000'
            },
            new Map<String, Object>{
                'asset' => 'f4364875e75320d405ceadebdf0db63fadaff55c72d4ff6b82f0676a434152474f',
                'amount' => '5000000'
            }
        };
        String memo = 'Test multi-asset transaction';
        
        Test.startTest();
            String result = WalletController.createMultiAssetOutboundTransaction(wallet.Id, toAddress, assets, memo);
        Test.stopTest();
        
        Assert.isNotNull(result, 'Should return transaction ID');
        
        Outbound_Transaction__c createdTx = [SELECT Id, To_Address__c, Memo__c, Transaction_Status__c, Approved__c 
                                           FROM Outbound_Transaction__c WHERE Id = :result];
        Assert.areEqual(toAddress, createdTx.To_Address__c, 'Should set correct to address');
        Assert.areEqual(memo, createdTx.Memo__c, 'Should set correct memo');
        Assert.areEqual(ConstantsAda.STATUS_READY_TO_SIGN, createdTx.Transaction_Status__c, 'Should set correct status');
        Assert.areEqual(ConstantsAda.STATUS_NOT_APPROVED, createdTx.Approved__c, 'Should set correct approval status');
        
        List<Outbound_Transaction_Line__c> lines = [SELECT Id, Asset__c, Amount__c 
                                                   FROM Outbound_Transaction_Line__c 
                                                   WHERE Outbound_Transaction__c = :result];
        Assert.areEqual(2, lines.size(), 'Should create correct number of transaction lines');
    }
    
    @IsTest
    static void createMultiAssetOutboundTransactionShouldThrowExceptionWhenToAddressIsBlank() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        List<Map<String, Object>> assets = new List<Map<String, Object>>{
            new Map<String, Object>{
                'asset' => 'ADA',
                'amount' => '1000000'
            }
        };
        
        Test.startTest();
            try {
                WalletController.createMultiAssetOutboundTransaction(wallet.Id, '', assets, 'Test');
                Assert.fail('Should throw exception for blank to address');
            } catch (AuraHandledException e) {
                Assert.isNotNull(e.getMessage(), 'Should throw exception with message');
            }
        Test.stopTest();
    }
    
    @IsTest
    static void createMultiAssetOutboundTransactionShouldThrowExceptionWhenAssetsIsEmpty() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        
        Test.startTest();
            try {
                WalletController.createMultiAssetOutboundTransaction(wallet.Id, 'addr_test', new List<Map<String, Object>>(), 'Test');
                Assert.fail('Should throw exception for empty assets');
            } catch (AuraHandledException e) {
                Assert.isNotNull(e.getMessage(), 'Should throw exception with message');
            }
        Test.stopTest();
    }
    
    @IsTest
    static void createOutboundTransactionShouldCreateTransactionWhenValidInput() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        String toAddress = 'addr_test_recipient';
        String amount = '1000000';
        String asset = 'ADA';
        String memo = 'Test single asset transaction';
        
        Test.startTest();
            String result = WalletController.createOutboundTransaction(wallet.Id, toAddress, amount, asset, memo);
        Test.stopTest();
        
        Assert.isNotNull(result, 'Should return transaction ID');
        
        Outbound_Transaction__c createdTx = [SELECT Id, To_Address__c, Memo__c, Transaction_Status__c, Approved__c 
                                           FROM Outbound_Transaction__c WHERE Id = :result];
        Assert.areEqual(toAddress, createdTx.To_Address__c, 'Should set correct to address');
        Assert.areEqual(memo, createdTx.Memo__c, 'Should set correct memo');
        Assert.areEqual(ConstantsAda.STATUS_READY_TO_SIGN, createdTx.Transaction_Status__c, 'Should set correct status');
        Assert.areEqual(ConstantsAda.STATUS_NOT_APPROVED, createdTx.Approved__c, 'Should set correct approval status');
        
        List<Outbound_Transaction_Line__c> lines = [SELECT Id, Asset__c, Amount__c 
                                                   FROM Outbound_Transaction_Line__c 
                                                   WHERE Outbound_Transaction__c = :result];
        Assert.areEqual(1, lines.size(), 'Should create one transaction line');
        Assert.areEqual(asset, lines[0].Asset__c, 'Should set correct asset');
        Assert.areEqual(Decimal.valueOf(amount), lines[0].Amount__c, 'Should set correct amount');
    }
    
    @IsTest
    static void createOutboundTransactionShouldThrowExceptionWhenToAddressIsBlank() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        
        Test.startTest();
            try {
                WalletController.createOutboundTransaction(wallet.Id, '', '1000000', 'ADA', 'Test');
                Assert.fail('Should throw exception for blank to address');
            } catch (AuraHandledException e) {
                Assert.isNotNull(e.getMessage(), 'Should throw exception with message');
            }
        Test.stopTest();
    }
    
    @IsTest
    static void createOutboundTransactionShouldThrowExceptionWhenAmountIsBlank() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        
        Test.startTest();
            try {
                WalletController.createOutboundTransaction(wallet.Id, 'addr_test', '', 'ADA', 'Test');
                Assert.fail('Should throw exception for blank amount');
            } catch (AuraHandledException e) {
                Assert.isNotNull(e.getMessage(), 'Should throw exception with message');
            }
        Test.stopTest();
    }
    
    @IsTest
    static void createOutboundTransactionShouldThrowExceptionWhenAssetIsBlank() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        
        Test.startTest();
            try {
                WalletController.createOutboundTransaction(wallet.Id, 'addr_test', '1000000', '', 'Test');
                Assert.fail('Should throw exception for blank asset');
            } catch (AuraHandledException e) {
                Assert.isNotNull(e.getMessage(), 'Should throw exception with message');
            }
        Test.stopTest();
    }
    
    @IsTest
    static void createOutboundTransactionShouldThrowExceptionWhenAmountIsInvalid() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        
        Test.startTest();
            try {
                WalletController.createOutboundTransaction(wallet.Id, 'addr_test', 'invalid', 'ADA', 'Test');
                Assert.fail('Should throw exception for invalid amount');
            } catch (AuraHandledException e) {
                Assert.isNotNull(e.getMessage(), 'Should throw exception with message');
            }
        Test.stopTest();
    }
    
    @IsTest
    static void createOutboundTransactionShouldThrowExceptionWhenAmountIsZero() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        
        Test.startTest();
            try {
                WalletController.createOutboundTransaction(wallet.Id, 'addr_test', '0', 'ADA', 'Test');
                Assert.fail('Should throw exception for zero amount');
            } catch (AuraHandledException e) {
                Assert.isNotNull(e.getMessage(), 'Should throw exception with message');
            }
        Test.stopTest();
    }
    
    @IsTest
    static void createOutboundTransactionShouldThrowExceptionWhenAmountIsNegative() {
        Wallet__c wallet = [SELECT Id FROM Wallet__c LIMIT 1];
        
        Test.startTest();
            try {
                WalletController.createOutboundTransaction(wallet.Id, 'addr_test', '-1000000', 'ADA', 'Test');
                Assert.fail('Should throw exception for negative amount');
            } catch (AuraHandledException e) {
                Assert.isNotNull(e.getMessage(), 'Should throw exception with message');
            }
        Test.stopTest();
    }
} 