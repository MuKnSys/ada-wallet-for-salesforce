public with sharing class WalletController {    
    /**
     * Get asset summary for a wallet (all assets across all UTXO addresses)
     * @param walletId The wallet ID to get assets for
     * @return Map with asset summary data
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getWalletAssetSummary(Id walletId) {
        try {
            if (walletId == null) {
                throw new AuraHandledException('Wallet ID cannot be null');
            }
            
            // Get all UTXO addresses for this wallet
            List<UTXO_Address__c> utxoAddresses = UTXOAddressSelector.getAddressesByWalletId(walletId);
            
            if (utxoAddresses.isEmpty()) {
                return new Map<String, Object>{
                    'success' => true,
                    'adaBalance' => 0,
                    'tokens' => new List<Object>(),
                    'totalAssets' => 0,
                    'message' => 'No UTXO addresses found for this wallet'
                };
            }
            
            Set<Id> utxoAddressIds = new Set<Id>();
            for (UTXO_Address__c addr : utxoAddresses) {
                utxoAddressIds.add(addr.Id);
            }
            
            // Get all assets for these addresses, aggregated by Asset
            AggregateResult[] assetAggregates = UTXOAssetSelector.getAssetAggregatesByUtxoAddressIds(utxoAddressIds);

            // Build a set of all asset units
            Set<String> assetUnits = new Set<String>();
            for (AggregateResult ar : assetAggregates) {
                assetUnits.add(String.valueOf(ar.get('Asset__c')));
            }
            // Query one UTXO_Asset__c per asset to get Icon__c
            Map<String, String> assetToIcon = new Map<String, String>();
            List<UTXO_Asset__c> allAssetsWithIcons = UTXOAssetSelector.getAllAssetsByUtxoAddressIds(utxoAddressIds);
            for (UTXO_Asset__c asset : allAssetsWithIcons) {
                if (assetUnits.contains(asset.Asset__c) && asset.Icon__c != null && !assetToIcon.containsKey(asset.Asset__c)) {
                    assetToIcon.put(asset.Asset__c, asset.Icon__c);
                }
            }
            
            Decimal adaBalance = 0;
            List<Map<String, Object>> tokens = new List<Map<String, Object>>();
            
            for (AggregateResult ar : assetAggregates) {
                String unit = String.valueOf(ar.get('Asset__c'));
                Decimal totalAmount = (Decimal) ar.get('totalAmount');
                Decimal totalValue = (Decimal) ar.get('totalValue');
                String assetName = String.valueOf(ar.get('assetName'));
                Integer decimals = ar.get('decimals') != null ? Integer.valueOf(ar.get('decimals')) : 0;
                String policyId = String.valueOf(ar.get('policyId'));
                String fingerprint = String.valueOf(ar.get('fingerprint'));
                
                if (unit == 'ADA') {
                    // For ADA, use the Value__c field which converts lovelace to ADA
                    adaBalance = totalValue != null ? totalValue : 0;
                } else {
                    // For tokens, add to tokens list
                    // Use Amount__c if Value__c is 0 or null, otherwise use Value__c
                    Decimal displayAmount = (totalValue != null && totalValue > 0) ? totalValue : totalAmount;
                    
                    Map<String, Object> tokenInfo = new Map<String, Object>{
                        'unit' => unit,
                        'name' => assetName != null ? assetName : unit,
                        'symbol' => unit, // Use Asset__c field as the ticker/symbol
                        'amount' => displayAmount, // Use appropriate amount
                        'rawAmount' => totalAmount, // Keep raw amount for reference
                        'decimals' => decimals,
                        'policyId' => policyId != 'null' ? policyId : null,
                        'fingerprint' => fingerprint != 'null' ? fingerprint : null,
                        'icon' => assetToIcon.containsKey(unit) ? assetToIcon.get(unit) : 'utility:money'
                    };
                    tokens.add(tokenInfo);
                }
            }
            
            Map<String, Object> result = new Map<String, Object>{
                'success' => true,
                'adaBalance' => adaBalance,
                'tokens' => tokens,
                'totalAssets' => assetAggregates.size(),
                'message' => 'Asset summary retrieved successfully'
            };
            
            return result;
            
        } catch (Exception e) {
            throw new AuraHandledException('Failed to get wallet asset summary: ' + e.getMessage());
        }
    }
    
    /**
     * Get all transactions for a wallet
     * @param walletId The wallet ID to get transactions for
     * @return Map with transaction data
     */
    @AuraEnabled
    public static Map<String, Object> fetchWalletTransactions(Id walletId) {
        try {
            if (walletId == null) {
                throw new AuraHandledException('Wallet ID cannot be null');
            }
            
            // Get Inbound Transactions
            List<Inbound_Transaction__c> inboundTxs = InboundTransactionSelector.getInboundTransactionsByWalletId(walletId);
            
            // Get Outbound Transactions with joined lines
            List<Outbound_Transaction__c> outboundTxs = OutboundTransactionSelector.getOutboundTransactionsByWalletId(walletId);
            
            // Map inbound transactions for LWC
            List<Map<String, Object>> inbound = new List<Map<String, Object>>();
            for (Inbound_Transaction__c tx : inboundTxs) {
                inbound.add(new Map<String, Object>{
                    'Id' => tx.Id,
                    'Name' => tx.Name,
                    'Transaction_Hash__c' => tx.Transaction_Hash__c,
                    'CreatedDate' => tx.CreatedDate,
                    'UTXO_Address__c' => tx.UTXO_Address__c,
                    'type' => 'inbound'
                });
            }
            
            // Map outbound transactions for LWC
            List<Map<String, Object>> outbound = new List<Map<String, Object>>();
            for (Outbound_Transaction__c tx : outboundTxs) {
                List<Map<String, Object>> lines = new List<Map<String, Object>>();
                if (tx.Outbound_Transaction_Lines__r != null) {
                    for (Outbound_Transaction_Line__c line : tx.Outbound_Transaction_Lines__r) {
                        lines.add(new Map<String, Object>{
                            'Id' => line.Id,
                            'Asset__c' => line.Asset__c,
                            'Amount__c' => line.Amount__c
                        });
                    }
                }
                outbound.add(new Map<String, Object>{
                    'Id' => tx.Id,
                    'Name' => tx.Name,
                    'Transaction_Hash__c' => tx.Transaction_Hash__c,
                    'Transaction_Status__c' => tx.Transaction_Status__c,
                    'Memo__c' => tx.Memo__c,
                    'CreatedDate' => tx.CreatedDate,
                    'type' => 'outbound',
                    'lines' => lines
                });
            }
            
            Map<String, Object> result = new Map<String, Object>{
                'success' => true,
                'inbound' => inbound,
                'outbound' => outbound,
                'totalInbound' => inbound.size(),
                'totalOutbound' => outbound.size(),
                'message' => 'Transactions retrieved successfully'
            };
            
            return result;
            
        } catch (Exception e) {
            throw new AuraHandledException('Failed to get wallet transactions: ' + e.getMessage());
        }
    }
    
    /**
     * Synchronizes both assets and transactions for a UTXO address
     * @param utxoAddressId The UTXO Address ID to sync
     * @return Map with combined results
     */
    @AuraEnabled
    public static Map<String, Object> syncAssetsAndTransactions(Id utxoAddressId) {
        try {
            return UTXOHelper.syncAssetsAndTransactions(utxoAddressId);
        } catch (Exception e) {
            throw new AuraHandledException('Error syncing assets and transactions: ' + e.getMessage());
        }
    }
    
    /**
     * Get all UTXO addresses for a wallet
     * @param walletId The wallet ID to get addresses for
     * @return List of UTXO addresses
     */
    @AuraEnabled(cacheable=true)
    public static List<UTXO_Address__c> getAllWalletAddresses(String walletId) {
        try {            
            return UTXOAddressSelector.getAddressesByWalletId(walletId);
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving wallet addresses: ' + e.getMessage());
        }
    }
    
    /**
     * Get the first unused receiving address for a wallet
     * @param walletId The wallet ID to get address for
     * @return The first unused receiving address or null if none found
     */
    @AuraEnabled(cacheable=true)
    public static String getFirstUnusedReceivingAddress(String walletId) {
        try {
            List<UTXO_Address__c> addrs = UTXOAddressSelector.getFirstUnusedAddressByType(walletId, '0');
            return addrs.isEmpty() ? null : addrs[0].Address__c;
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching unused receiving address: ' + e.getMessage());
        }
    }
    
    /**
     * Get all UTXO assets for a wallet
     * @param walletId The wallet ID to get assets for
     * @return List of UTXO assets
     */
    @AuraEnabled(cacheable=true)
    public static List<UTXO_Asset__c> getAllUtxoAssetsForWallet(String walletId) {
        try {
            return UTXOAssetSelector.getAssetsByWalletId(walletId);
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving UTXO assets: ' + e.getMessage());
        }
    }
    
    /**
     * Create a multi-asset outbound transaction
     * @param walletId The wallet ID
     * @param toAddress The recipient address
     * @param assets List of assets with amounts
     * @param memo Optional memo
     * @return The outbound transaction ID
     */
    @AuraEnabled
    public static String createMultiAssetOutboundTransaction(String walletId, String toAddress, List<Map<String, Object>> assets, String memo) {
        try {
            if (String.isBlank(toAddress)) {
                throw new AuraHandledException('To Address is required');
            }
            if (assets == null || assets.isEmpty()) {
                throw new AuraHandledException('At least one asset is required');
            }

            Outbound_Transaction__c txRecord = new Outbound_Transaction__c(
                Wallet__c = walletId,
                To_Address__c = toAddress,
                Approved__c = OutboundTransactionHelper.APPROVAL_STATUS_NOT_APPROVED,
                Transaction_Status__c = OutboundTransactionHelper.STATUS_READY_TO_SIGN,
                Memo__c = String.isBlank(memo) ? null : memo
            );
            SObjectAccessDecision decision = Security.stripInaccessible(AccessType.CREATABLE, new List<Outbound_Transaction__c>{txRecord});
            insert decision.getRecords();
            Id outboundId = decision.getRecords()[0].Id;

            List<Outbound_Transaction_Line__c> lines = new List<Outbound_Transaction_Line__c>();
            for (Map<String, Object> assetMap : assets) {
                Decimal lineAmount;
                String lineAsset;
                try {
                    lineAmount = Decimal.valueOf(String.valueOf(assetMap.get('amount')));
                } catch (Exception e) {
                    continue;
                }
                lineAsset = String.valueOf(assetMap.get('asset'));
                if (String.isBlank(lineAsset)) {
                    continue;
                }
                lines.add(new Outbound_Transaction_Line__c(
                    Outbound_Transaction__c = outboundId,
                    Amount__c = lineAmount,
                    Asset__c = lineAsset
                ));
            }
            if (!lines.isEmpty()) {
                SObjectAccessDecision lineDecision = Security.stripInaccessible(AccessType.CREATABLE, lines);
                insert lineDecision.getRecords();
            }

            return outboundId;
        } catch (Exception e) {
            throw new AuraHandledException('Error creating multi-asset outbound transaction: ' + e.getMessage());
        }
    }
    
    /**
     * Create a single asset outbound transaction
     * @param walletId The wallet ID
     * @param toAddress The recipient address
     * @param amount The amount to send
     * @param asset The asset to send
     * @param memo Optional memo
     * @return The outbound transaction ID
     */
    @AuraEnabled
    public static String createOutboundTransaction(String walletId, String toAddress, String amount, String asset, String memo) {
        try {
            if (String.isBlank(toAddress)) {
                throw new AuraHandledException('To Address is required');
            }
            if (String.isBlank(amount)) {
                throw new AuraHandledException('Amount is required');
            }
            if (String.isBlank(asset)) {
                throw new AuraHandledException('Asset is required');
            }

            Decimal amountDecimal;
            try {
                amountDecimal = Decimal.valueOf(amount);
            } catch (Exception e) {
                throw new AuraHandledException('Invalid amount format');
            }

            if (amountDecimal <= 0) {
                throw new AuraHandledException('Amount must be greater than 0');
            }

            Outbound_Transaction__c txRecord = new Outbound_Transaction__c(
                Wallet__c = walletId,
                To_Address__c = toAddress,
                Approved__c = 'Not Approved',
                Transaction_Status__c = 'Ready to Sign',
                Memo__c = String.isBlank(memo) ? null : memo
            );

            SObjectAccessDecision decision = Security.stripInaccessible(AccessType.CREATABLE, new List<Outbound_Transaction__c>{txRecord});
            insert decision.getRecords();
            Id outboundId = decision.getRecords()[0].Id;

            Outbound_Transaction_Line__c line = new Outbound_Transaction_Line__c(
                Outbound_Transaction__c = outboundId,
                Amount__c = amountDecimal,
                Asset__c = asset
            );
            SObjectAccessDecision lineDecision = Security.stripInaccessible(AccessType.CREATABLE, new List<Outbound_Transaction_Line__c>{line});
            insert lineDecision.getRecords();

            return outboundId;
        } catch (Exception e) {
            throw new AuraHandledException('Error creating outbound transaction: ' + e.getMessage());
        }
    }
} 